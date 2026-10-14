"""Checked native Mojo rigid-body impulses and bounded single-body dynamics.

SI units; right-handed world coordinates. Position is the centre of mass and
orientation maps principal inertia axes into world space. Accumulated forces
and torques act over one explicit integration call. No collision/contact solver.
"""
from std.math import isfinite, sqrt, ceil
from .math3d import Vec3
from .transform3d import Quaternion


def _finite_vector(v: Vec3) raises:
    if not isfinite(v.x) or not isfinite(v.y) or not isfinite(v.z):
        raise Error("Rigid-body vectors must be finite")


def _zero_vector(v: Vec3) -> Bool:
    return v.x == 0 and v.y == 0 and v.z == 0


def _rotation(q: Quaternion) raises -> Quaternion:
    if not isfinite(q.x) or not isfinite(q.y) or not isfinite(q.z) or not isfinite(q.w):
        raise Error("Rigid-body orientation must be finite")
    var scale = max(max(abs(q.x), abs(q.y)), max(abs(q.z), abs(q.w)))
    if scale == 0:
        raise Error("Rigid-body orientation must have nonzero length")
    # Scale first so a finite quaternion cannot overflow its squared norm.
    return Quaternion(q.x / scale, q.y / scale, q.z / scale, q.w / scale).normalized()


def _max_component(v: Vec3) -> Float64:
    return max(abs(v.x), max(abs(v.y), abs(v.z)))


def _advance_rotation(q: Quaternion, omega: Vec3, dt: Float64) raises -> Quaternion:
    _finite_vector(omega)
    var rotation = _rotation(q)
    var scale = _max_component(omega)
    if scale == 0:
        return rotation
    var scaled = Vec3(omega.x / scale, omega.y / scale, omega.z / scale)
    var length = sqrt(scaled.dot(scaled))
    var angle = (scale * dt) * length
    if not isfinite(angle) or angle > 0.25:
        raise Error("Angular substep exceeds 0.25 radians; reduce max_substep")
    if angle == 0:
        return rotation
    # Angular velocity is world-space, so the increment multiplies on the left.
    return _rotation(Quaternion.axis_angle(scaled * (1 / length), angle) * rotation)


struct MassProperties3D(ImplicitlyCopyable, Movable):
    var mass: Float64
    var inertia: Vec3

    def __init__(out self, mass: Float64 = 0, inertia: Vec3 = Vec3(0, 0, 0)) raises:
        self.mass = mass
        self.inertia = inertia
        self.validate()

    def validate(self) raises:
        _finite_vector(self.inertia)
        if not isfinite(self.mass) or self.mass < 0:
            raise Error("Rigid-body mass must be finite and nonnegative")
        if self.mass == 0:
            if not _zero_vector(self.inertia):
                raise Error("Fixed-body mass and inertia must both be zero")
            return
        if self.inertia.x <= 0 or self.inertia.y <= 0 or self.inertia.z <= 0:
            raise Error("Dynamic principal inertia must be positive")
        if not isfinite(1 / self.mass) or not isfinite(1 / self.inertia.x) or not isfinite(1 / self.inertia.y) or not isfinite(1 / self.inertia.z):
            raise Error("Inverse mass and inertia must be representable")
        # Principal moments of a physical mass distribution obey triangle
        # inequalities. Normalized comparison avoids overflowing their sums.
        var scale = max(self.inertia.x, max(self.inertia.y, self.inertia.z))
        var v = self.inertia * (1 / scale)
        if v.x > v.y + v.z + 1e-12 or v.y > v.x + v.z + 1e-12 or v.z > v.x + v.y + 1e-12:
            raise Error("Principal inertia is not a physical mass distribution")

    @staticmethod
    def fixed() raises -> Self:
        # Zero is a fixed-body marker, not a dynamic zero-mass object.
        return Self()

    @staticmethod
    def sphere(mass: Float64, radius: Float64) raises -> Self:
        if not isfinite(mass) or mass <= 0 or not isfinite(radius) or radius <= 0:
            raise Error("Sphere mass and radius must be finite and positive")
        var moment = 0.4 * mass * radius * radius
        return Self(mass, Vec3(moment, moment, moment))

    @staticmethod
    def box(mass: Float64, half_extents: Vec3) raises -> Self:
        _finite_vector(half_extents)
        if not isfinite(mass) or mass <= 0 or half_extents.x <= 0 or half_extents.y <= 0 or half_extents.z <= 0:
            raise Error("Box mass and half extents must be finite and positive")
        var x2 = half_extents.x * half_extents.x
        var y2 = half_extents.y * half_extents.y
        var z2 = half_extents.z * half_extents.z
        return Self(mass, Vec3(mass * (y2 + z2) / 3, mass * (x2 + z2) / 3, mass * (x2 + y2) / 3))

    def inverse_mass(self) raises -> Float64:
        self.validate()
        return 0.0 if self.mass == 0 else 1 / self.mass


struct RigidBody3D(ImplicitlyCopyable, Movable):
    var properties: MassProperties3D
    var position: Vec3
    var orientation: Quaternion
    var linear_velocity: Vec3
    var angular_velocity: Vec3
    var force: Vec3
    var torque: Vec3

    def __init__(out self, properties: MassProperties3D, position: Vec3 = Vec3(0, 0, 0), orientation: Quaternion = Quaternion()) raises:
        properties.validate()
        _finite_vector(position)
        var rotation = _rotation(orientation)
        self.properties = properties
        self.position = position
        self.orientation = rotation
        self.linear_velocity = Vec3(0, 0, 0)
        self.angular_velocity = Vec3(0, 0, 0)
        self.force = Vec3(0, 0, 0)
        self.torque = Vec3(0, 0, 0)

    def validate(self) raises:
        self.properties.validate()
        _finite_vector(self.position)
        _finite_vector(self.linear_velocity)
        _finite_vector(self.angular_velocity)
        _finite_vector(self.force)
        _finite_vector(self.torque)
        _ = _rotation(self.orientation)
        if self.properties.mass == 0 and (not _zero_vector(self.linear_velocity) or not _zero_vector(self.angular_velocity)):
            raise Error("Fixed-body velocities must be zero")

    def inverse_inertia(self, world_vector: Vec3) raises -> Vec3:
        """Apply R diag(1/I) R^T to a world-space angular impulse."""
        self.validate()
        _finite_vector(world_vector)
        if self.properties.mass == 0:
            return Vec3(0, 0, 0)
        var q = _rotation(self.orientation)
        var local = Quaternion(-q.x, -q.y, -q.z, q.w).rotate(world_vector)
        var diagonal = self.properties.inertia
        var result = q.rotate(Vec3(local.x / diagonal.x, local.y / diagonal.y, local.z / diagonal.z))
        _finite_vector(result)
        return result

    def linear_momentum(self) raises -> Vec3:
        self.validate()
        var result = self.linear_velocity * self.properties.mass
        _finite_vector(result)
        return result

    def angular_momentum(self) raises -> Vec3:
        """World-space spin momentum about the centre of mass."""
        self.validate()
        if self.properties.mass == 0:
            return Vec3(0, 0, 0)
        var q = _rotation(self.orientation)
        var local = Quaternion(-q.x, -q.y, -q.z, q.w).rotate(self.angular_velocity)
        var diagonal = self.properties.inertia
        var result = q.rotate(Vec3(local.x * diagonal.x, local.y * diagonal.y, local.z * diagonal.z))
        _finite_vector(result)
        return result

    def kinetic_energy(self) raises -> Float64:
        self.validate()
        var value = 0.5 * (self.linear_velocity.dot(self.linear_momentum()) + self.angular_velocity.dot(self.angular_momentum()))
        if not isfinite(value) or value < 0:
            raise Error("Rigid-body energy is not representable")
        return value

    def point_velocity(self, offset: Vec3) raises -> Vec3:
        """Velocity at a world-space displacement from the centre of mass."""
        self.validate()
        _finite_vector(offset)
        var result = self.linear_velocity + self.angular_velocity.cross(offset)
        _finite_vector(result)
        return result

    def apply_impulse(mut self, impulse: Vec3, offset: Vec3 = Vec3(0, 0, 0)) raises:
        """Apply a world impulse at a COM-relative world offset; no dt scaling.

        Inputs and complete resulting velocities are checked before mutation.
        An offset avoids subtracting distant absolute positions inside the API.
        """
        self.validate()
        _finite_vector(impulse)
        _finite_vector(offset)
        if self.properties.mass == 0:
            return
        var next_linear = self.linear_velocity + impulse * self.properties.inverse_mass()
        var next_angular = self.angular_velocity + self.inverse_inertia(offset.cross(impulse))
        _finite_vector(next_linear)
        _finite_vector(next_angular)
        self.linear_velocity = next_linear
        self.angular_velocity = next_angular

    def apply_angular_impulse(mut self, impulse: Vec3) raises:
        self.validate()
        _finite_vector(impulse)
        if self.properties.mass == 0:
            return
        var result = self.angular_velocity + self.inverse_inertia(impulse)
        _finite_vector(result)
        self.angular_velocity = result

    def apply_force(mut self, force: Vec3, offset: Vec3 = Vec3(0, 0, 0)) raises:
        """Accumulate world force in N and offset-cross-force torque in N m.

        Offset is a world displacement from COM at accumulation time, not a
        persistent local attachment. Accumulated world force/torque stay constant
        during the next integration interval, then clear only on success.
        """
        self.validate()
        _finite_vector(force)
        _finite_vector(offset)
        if self.properties.mass == 0:
            return
        var next_force = self.force + force
        var next_torque = self.torque + offset.cross(force)
        _finite_vector(next_force)
        _finite_vector(next_torque)
        self.force = next_force
        self.torque = next_torque

    def apply_torque(mut self, torque: Vec3) raises:
        self.validate()
        _finite_vector(torque)
        if self.properties.mass == 0:
            return
        var result = self.torque + torque
        _finite_vector(result)
        self.torque = result

    def integrate(mut self, dt: Float64, gravity: Vec3 = Vec3(0, -9.81, 0), *, max_substep: Float64 = 1.0 / 120) raises -> Int:
        """Advance a single body's COM/pose; return the number of substeps.

        dt is seconds in (0, .25]. max_substep is an explicit ceiling in
        (0, 1/30], default 1/120; at most 32 substeps. Translation uses midpoint
        velocity for constant acceleration. Rotation solves a bounded angular-
        momentum midpoint on quaternions; energy is approximate, not exact.
        Failed validation, overflow, angular budget or convergence leaves the
        entire body and both accumulators unchanged.
        """
        self.validate()
        _finite_vector(gravity)
        if not isfinite(dt) or dt <= 0 or dt > 0.25:
            raise Error("Rigid-body dt must be finite and in (0, 0.25]")
        if not isfinite(max_substep) or max_substep <= 0 or max_substep > 1.0 / 30:
            raise Error("max_substep must be finite and in (0, 1/30]")
        var ratio = dt / max_substep
        if not isfinite(ratio) or ratio > 32:
            raise Error("Rigid-body integration exceeds 32 substeps")
        var steps = max(1, Int(ceil(ratio)))
        if self.properties.mass == 0:
            self.force = Vec3(0, 0, 0)
            self.torque = Vec3(0, 0, 0)
            return 0
        var h = dt / Float64(steps)
        var acceleration = gravity + self.force * self.properties.inverse_mass()
        _finite_vector(acceleration)
        var momentum = self.angular_momentum()
        var candidate = self
        for _ in range(steps):
            var next_linear = candidate.linear_velocity + acceleration * h
            var next_position = candidate.position + (candidate.linear_velocity * 0.5 + next_linear * 0.5) * h
            var midpoint_momentum = momentum + self.torque * (h * 0.5)
            var next_momentum = momentum + self.torque * h
            _finite_vector(next_linear)
            _finite_vector(next_position)
            _finite_vector(midpoint_momentum)
            _finite_vector(next_momentum)

            var estimate = candidate.inverse_inertia(midpoint_momentum)
            var converged = False
            for _ in range(16):
                var midpoint = candidate
                midpoint.orientation = _advance_rotation(candidate.orientation, estimate, h * 0.5)
                var refined = midpoint.inverse_inertia(midpoint_momentum)
                var difference = refined - estimate
                _finite_vector(difference)
                var change = _max_component(difference)
                estimate = refined
                if change <= 1e-12 * (1 + _max_component(refined)):
                    converged = True
                    break
            if not converged:
                raise Error("Angular midpoint did not converge; reduce max_substep")
            var endpoint = candidate
            endpoint.orientation = _advance_rotation(candidate.orientation, estimate, h)
            var next_angular = endpoint.inverse_inertia(next_momentum)
            _finite_vector(next_angular)
            candidate.position = next_position
            candidate.linear_velocity = next_linear
            candidate.orientation = endpoint.orientation
            candidate.angular_velocity = next_angular
            momentum = next_momentum

        candidate.force = Vec3(0, 0, 0)
        candidate.torque = Vec3(0, 0, 0)
        candidate.validate()
        self.position = candidate.position
        self.orientation = candidate.orientation
        self.linear_velocity = candidate.linear_velocity
        self.angular_velocity = candidate.angular_velocity
        self.force = candidate.force
        self.torque = candidate.torque
        return steps
