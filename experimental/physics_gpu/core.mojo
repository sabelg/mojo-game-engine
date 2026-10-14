"""G01 device-callable Float64 integration. No host exceptions or allocation.

The unchanged rigidbody3d implementation is the independent CPU oracle.
Float64 is a correctness profile, not a GPU performance promise.
"""
from std.math import isfinite, sqrt, ceil
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion

comptime OK = Int32(0)
comptime INVALID = Int32(1)
comptime TIMESTEP = Int32(2)
comptime SUBSTEP = Int32(3)
comptime OVERFLOW = Int32(4)
comptime ANGULAR = Int32(5)
comptime CONVERGENCE = Int32(6)

def finite(v: Vec3) -> Bool:
    return isfinite(v.x) and isfinite(v.y) and isfinite(v.z)

def component(v: Vec3) -> Float64:
    return max(abs(v.x), max(abs(v.y), abs(v.z)))

def qfinite(q: Quaternion) -> Bool:
    return isfinite(q.x) and isfinite(q.y) and isfinite(q.z) and isfinite(q.w)

def qscale(q: Quaternion) -> Float64:
    return max(max(abs(q.x), abs(q.y)), max(abs(q.z), abs(q.w)))

def rotation(q: Quaternion) -> Quaternion:
    var scale = qscale(q)
    return Quaternion(q.x / scale, q.y / scale, q.z / scale, q.w / scale).normalized()

def inverse(q: Quaternion, inertia: Vec3, value: Vec3) -> Vec3:
    var r = rotation(q)
    var local = Quaternion(-r.x, -r.y, -r.z, r.w).rotate(value)
    return r.rotate(Vec3(local.x / inertia.x, local.y / inertia.y, local.z / inertia.z))

def momentum(q: Quaternion, inertia: Vec3, omega: Vec3) -> Vec3:
    var r = rotation(q)
    var local = Quaternion(-r.x, -r.y, -r.z, r.w).rotate(omega)
    return r.rotate(Vec3(local.x * inertia.x, local.y * inertia.y, local.z * inertia.z))

@fieldwise_init
struct RotationResult(ImplicitlyCopyable, Movable):
    var q: Quaternion
    var status: Int32

def advance(q: Quaternion, omega: Vec3, dt: Float64) -> RotationResult:
    if not finite(omega):
        return RotationResult(q, OVERFLOW)
    var r = rotation(q)
    var scale = component(omega)
    if scale == 0:
        return RotationResult(r, OK)
    var scaled = Vec3(omega.x / scale, omega.y / scale, omega.z / scale)
    var length = sqrt(scaled.dot(scaled))
    var angle = (scale * dt) * length
    if not isfinite(angle) or angle > 0.25:
        return RotationResult(q, ANGULAR)
    if angle == 0:
        return RotationResult(r, OK)
    # Locked Mojo std.math lacks NVIDIA Float64 sin/cos. Here angle/2 is
    # bounded by .125, so fixed Taylor polynomials avoid Float32 conversion.
    # Terms through sin degree 11 / cos degree 12; truncation < 3e-22 on
    # this interval. Differential/conservation tests still gate rounding error.
    var x = angle * .5
    var z = x * x
    var sine = x * (1 + z * (-1.0/6 + z * (1.0/120 + z * (-1.0/5040 + z * (1.0/362880 + z * (-1.0/39916800))))))
    var cosine = 1 + z * (-1.0/2 + z * (1.0/24 + z * (-1.0/720 + z * (1.0/40320 + z * (-1.0/3628800 + z * (1.0/479001600))))))
    var axis = (scaled * (1 / length)).unit()
    var next = Quaternion(axis.x * sine, axis.y * sine, axis.z * sine, cosine) * r
    if not qfinite(next) or qscale(next) == 0:
        return RotationResult(q, OVERFLOW)
    return RotationResult(rotation(next), OK)

@fieldwise_init
struct BodyState(ImplicitlyCopyable, Movable):
    var mass: Float64
    var inertia: Vec3
    var position: Vec3
    var orientation: Quaternion
    var linear: Vec3
    var angular: Vec3
    var force: Vec3
    var torque: Vec3

    def valid(self) -> Bool:
        if not isfinite(self.mass) or self.mass < 0 or not finite(self.inertia):
            return False
        if not finite(self.position) or not finite(self.linear) or not finite(self.angular) or not finite(self.force) or not finite(self.torque):
            return False
        if not qfinite(self.orientation) or qscale(self.orientation) == 0:
            return False
        if self.mass == 0:
            return component(self.inertia) == 0 and component(self.linear) == 0 and component(self.angular) == 0
        if self.inertia.x <= 0 or self.inertia.y <= 0 or self.inertia.z <= 0:
            return False
        if not isfinite(1 / self.mass) or not isfinite(1 / self.inertia.x) or not isfinite(1 / self.inertia.y) or not isfinite(1 / self.inertia.z):
            return False
        var v = self.inertia * (1 / component(self.inertia))
        return v.x <= v.y + v.z + 1e-12 and v.y <= v.x + v.z + 1e-12 and v.z <= v.x + v.y + 1e-12

    def integrate(mut self, dt: Float64, gravity: Vec3, ceiling: Float64) -> Int32:
        # This value is a private candidate: caller commits only after all bodies
        # report success. Failed candidates never publish to current device state.
        if not self.valid() or not finite(gravity):
            return INVALID
        if not isfinite(dt) or dt <= 0 or dt > .25 or not isfinite(ceiling) or ceiling <= 0 or ceiling > 1.0 / 30:
            return TIMESTEP
        var ratio = dt / ceiling
        if not isfinite(ratio) or ratio > 32:
            return SUBSTEP
        var steps = max(1, Int(ceil(ratio)))
        if self.mass == 0:
            self.force = Vec3(0, 0, 0)
            self.torque = Vec3(0, 0, 0)
            return OK
        var h = dt / Float64(steps)
        var acceleration = gravity + self.force * (1 / self.mass)
        var L = momentum(self.orientation, self.inertia, self.angular)
        if not finite(acceleration) or not finite(L):
            return OVERFLOW
        for _ in range(steps):
            var next_linear = self.linear + acceleration * h
            var next_position = self.position + (self.linear * .5 + next_linear * .5) * h
            var mid_L = L + self.torque * (h * .5)
            var next_L = L + self.torque * h
            if not finite(next_linear) or not finite(next_position) or not finite(mid_L) or not finite(next_L):
                return OVERFLOW
            var estimate = inverse(self.orientation, self.inertia, mid_L)
            var converged = False
            for _ in range(16):
                var midpoint = advance(self.orientation, estimate, h * .5)
                if midpoint.status != OK:
                    return midpoint.status
                var refined = inverse(midpoint.q, self.inertia, mid_L)
                var difference = refined - estimate
                if not finite(difference):
                    return OVERFLOW
                estimate = refined
                if component(difference) <= 1e-12 * (1 + component(refined)):
                    converged = True
                    break
            if not converged:
                return CONVERGENCE
            var endpoint = advance(self.orientation, estimate, h)
            if endpoint.status != OK:
                return endpoint.status
            var next_angular = inverse(endpoint.q, self.inertia, next_L)
            if not finite(next_angular):
                return OVERFLOW
            self.position = next_position
            self.linear = next_linear
            self.orientation = endpoint.q
            self.angular = next_angular
            L = next_L
        self.force = Vec3(0, 0, 0)
        self.torque = Vec3(0, 0, 0)
        return OK if self.valid() else OVERFLOW
