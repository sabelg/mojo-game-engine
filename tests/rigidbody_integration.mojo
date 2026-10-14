"""CPU-only R02a analytic, conservation, convergence and rejection tests."""
from std.math import sqrt, isfinite
from std.testing import assert_true, assert_equal, assert_raises
from mojo_game import MassProperties3D, RigidBody3D, Vec3, Quaternion


def near(a: Float64, b: Float64, tolerance: Float64 = 1e-10) raises:
    assert_true(abs(a - b) <= tolerance)


def vector_near(a: Vec3, b: Vec3, tolerance: Float64 = 1e-10) raises:
    near(a.x, b.x, tolerance)
    near(a.y, b.y, tolerance)
    near(a.z, b.z, tolerance)


def vector_exact(a: Vec3, b: Vec3) raises:
    assert_equal(a.x, b.x)
    assert_equal(a.y, b.y)
    assert_equal(a.z, b.z)


def state_exact(a: RigidBody3D, b: RigidBody3D) raises:
    vector_exact(a.position, b.position)
    vector_exact(a.linear_velocity, b.linear_velocity)
    vector_exact(a.angular_velocity, b.angular_velocity)
    vector_exact(a.force, b.force)
    vector_exact(a.torque, b.torque)
    assert_equal(a.orientation.x, b.orientation.x)
    assert_equal(a.orientation.y, b.orientation.y)
    assert_equal(a.orientation.z, b.orientation.z)
    assert_equal(a.orientation.w, b.orientation.w)


def rotation_error(a: Quaternion, b: Quaternion) -> Float64:
    # Compare frames, not quaternion sign; q and -q represent the same pose.
    return (a.rotate(Vec3(1, 0, 0)) - b.rotate(Vec3(1, 0, 0))).length() + (a.rotate(Vec3(0, 1, 0)) - b.rotate(Vec3(0, 1, 0))).length() + (a.rotate(Vec3(0, 0, 1)) - b.rotate(Vec3(0, 0, 1))).length()


def quaternion_unit(q: Quaternion) raises:
    near(sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w), 1, 2e-13)


def constant_force_and_gravity() raises:
    for hz in [30, 60, 120]:
        var h = 1.0 / Float64(hz)
        var body = RigidBody3D(MassProperties3D.sphere(2, 0.5))
        for _ in range(hz):
            body.apply_force(Vec3(4, 0, 0))
            _ = body.integrate(h, Vec3(0, 0, 0), max_substep=h)
        vector_near(body.linear_velocity, Vec3(2, 0, 0))
        vector_near(body.position, Vec3(1, 0, 0))
        vector_near(body.force, Vec3(0, 0, 0))
        for mass in [1.0, 100.0]:
            var falling = RigidBody3D(MassProperties3D.sphere(mass, 0.5), position=Vec3(0, 10, 0))
            for _ in range(hz): _ = falling.integrate(h, max_substep=h)
            near(falling.position.y, 5.095)
            near(falling.linear_velocity.y, -9.81)
    var force = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    var impulse = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    force.apply_force(Vec3(4, 0, 0))
    _ = force.integrate(0.25, Vec3(0, 0, 0))
    impulse.apply_impulse(Vec3(4, 0, 0))
    near(force.linear_velocity.x, 0.5)
    near(impulse.linear_velocity.x, 2)


def torque_and_offset_force() raises:
    for hz in [30, 60, 120]:
        var h = 1.0 / Float64(hz)
        var body = RigidBody3D(MassProperties3D.box(12, Vec3(1, 2, 3)))
        for _ in range(hz):
            body.apply_torque(Vec3(0, 0, 40))
            _ = body.integrate(h, Vec3(0, 0, 0), max_substep=h)
            quaternion_unit(body.orientation)
        vector_near(body.angular_velocity, Vec3(0, 0, 2))
        vector_near(body.angular_momentum(), Vec3(0, 0, 40))
        near(body.kinetic_energy(), 40)
        near(rotation_error(body.orientation, Quaternion.axis_angle(Vec3(0, 0, 1), 1)), 0)
    var body = RigidBody3D(MassProperties3D.box(12, Vec3(1, 2, 3)))
    body.apply_force(Vec3(0, 0, 20), Vec3(0, 1, 0))
    vector_near(body.force, Vec3(0, 0, 20))
    vector_near(body.torque, Vec3(20, 0, 0))
    _ = body.integrate(0.1, Vec3(0, 0, 0))
    near(body.linear_velocity.z, 1.0 / 6)
    near(body.position.z, 1.0 / 120)
    near(body.angular_velocity.x, 1.0 / 26)
    near(rotation_error(body.orientation, Quaternion.axis_angle(Vec3(1, 0, 0), 1.0 / 520)), 0)


def force_free_sphere() raises:
    for hz in [30, 60, 120]:
        var h = 1.0 / Float64(hz)
        var body = RigidBody3D(MassProperties3D.sphere(2, 0.5), position=Vec3(1, 2, 3))
        body.linear_velocity = Vec3(2, -1, 0.5)
        body.angular_velocity = Vec3(0, 0, 3)
        var momentum = body.angular_momentum()
        var energy = body.kinetic_energy()
        for _ in range(hz * 2):
            _ = body.integrate(h, Vec3(0, 0, 0), max_substep=h)
            quaternion_unit(body.orientation)
        vector_near(body.position, Vec3(5, 0, 4))
        vector_near(body.linear_velocity, Vec3(2, -1, 0.5))
        vector_near(body.angular_momentum(), momentum)
        near(body.kinetic_energy(), energy)
        near(rotation_error(body.orientation, Quaternion.axis_angle(Vec3(0, 0, 1), 6)), 0)


def accumulation_and_substeps() raises:
    var body = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    body.apply_force(Vec3(2, 0, 0))
    body.apply_force(Vec3(2, 0, 0))
    body.apply_torque(Vec3(0, 0, 0.2))
    assert_equal(body.integrate(1.0 / 30, Vec3(0, 0, 0)), 4)
    near(body.linear_velocity.x, 1.0 / 15)
    near(body.angular_velocity.z, 1.0 / 30)
    vector_near(body.force, Vec3(0, 0, 0))
    vector_near(body.torque, Vec3(0, 0, 0))
    var before = body.linear_velocity
    var spin = body.angular_velocity
    assert_equal(body.integrate(1.0 / 60, Vec3(0, 0, 0)), 2)
    vector_near(body.linear_velocity, before)
    vector_near(body.angular_velocity, spin)
    assert_equal(body.integrate(1.0 / 120, Vec3(0, 0, 0)), 1)
    var fixed = RigidBody3D(MassProperties3D.fixed(), position=Vec3(1, 2, 3))
    fixed.apply_force(Vec3(4, 5, 6), Vec3(1, 0, 0))
    fixed.apply_torque(Vec3(1, 2, 3))
    var old = fixed
    assert_equal(fixed.integrate(0.25), 0)
    state_exact(fixed, old)


def asymmetric_start() raises -> RigidBody3D:
    var body = RigidBody3D(MassProperties3D.box(12, Vec3(1, 2, 3)), orientation=Quaternion.axis_angle(Vec3(0, 1, 0), 0.35))
    body.angular_velocity = Vec3(0.7, 1.1, 1.5)
    return body


def asymmetric_run(hz: Int, energy_budget: Float64) raises -> RigidBody3D:
    var body = asymmetric_start()
    var h = 1.0 / Float64(hz)
    var momentum = body.angular_momentum()
    var energy = body.kinetic_energy()
    var max_relative_energy: Float64 = 0
    for _ in range(hz * 2):
        _ = body.integrate(h, Vec3(0, 0, 0), max_substep=h)
        quaternion_unit(body.orientation)
        vector_near(body.angular_momentum(), momentum, 5e-9)
        max_relative_energy = max(max_relative_energy, abs(body.kinetic_energy() - energy) / energy)
    print("asymmetric hz=", hz, " max_relative_energy=", max_relative_energy, sep="")
    assert_true(max_relative_energy <= energy_budget)
    return body


def asymmetric_conservation_and_convergence() raises:
    # Budgets are declared before execution. The approximate angular integrator
    # must meet them; do not redefine conservation as exact or loosen on failure.
    var coarse = asymmetric_run(30, 2e-4)
    var medium = asymmetric_run(60, 5e-5)
    var fine = asymmetric_run(120, 1.5e-5)
    var reference = asymmetric_run(960, 3e-7)
    var e30 = rotation_error(coarse.orientation, reference.orientation)
    var e60 = rotation_error(medium.orientation, reference.orientation)
    var e120 = rotation_error(fine.orientation, reference.orientation)
    print("frame_errors_30_60_120=", e30, ",", e60, ",", e120, sep="")
    assert_true(e30 > 1e-9)
    assert_true(e60 < e30 * 0.4)
    assert_true(e120 < e60 * 0.4)
    assert_true((fine.angular_velocity - reference.angular_velocity).length() < (medium.angular_velocity - reference.angular_velocity).length() * 0.4)
    # The default 1/120 ceiling makes ordinary external rates partition the same
    # internal interval. This is equivalence, distinct from refinement above.
    var defaults30 = asymmetric_start()
    var defaults60 = asymmetric_start()
    var defaults120 = asymmetric_start()
    for _ in range(60): _ = defaults30.integrate(1.0 / 30, Vec3(0, 0, 0))
    for _ in range(120): _ = defaults60.integrate(1.0 / 60, Vec3(0, 0, 0))
    for _ in range(240): _ = defaults120.integrate(1.0 / 120, Vec3(0, 0, 0))
    near(rotation_error(defaults30.orientation, defaults120.orientation), 0, 2e-9)
    near(rotation_error(defaults60.orientation, defaults120.orientation), 0, 2e-9)


def transactional_rejection() raises:
    var large = Float64(1e308)
    var infinity = large * large
    var nan = infinity - infinity
    var body = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    body.apply_force(Vec3(1, 2, 3))
    body.apply_torque(Vec3(0.1, 0.2, 0.3))
    var before = body
    with assert_raises(): body.apply_force(Vec3(nan, 0, 0))
    with assert_raises(): body.apply_force(Vec3(0, large, 0), Vec3(large, 0, 0))
    with assert_raises(): body.apply_torque(Vec3(0, 0, infinity))
    with assert_raises(): _ = body.integrate(nan)
    with assert_raises(): _ = body.integrate(0)
    with assert_raises(): _ = body.integrate(-0.1)
    with assert_raises(): _ = body.integrate(0.3)
    with assert_raises(): _ = body.integrate(0.1, Vec3(nan, 0, 0))
    with assert_raises(): _ = body.integrate(0.1, max_substep=0)
    with assert_raises(): _ = body.integrate(0.1, max_substep=0.1)
    with assert_raises(): _ = body.integrate(0.25, max_substep=1e-4)
    with assert_raises(): _ = body.integrate(0.25, max_substep=1e-308)
    state_exact(body, before)
    body.angular_velocity = Vec3(1000, 0, 0)
    before = body
    with assert_raises(): _ = body.integrate(1.0 / 120, Vec3(0, 0, 0))
    state_exact(body, before)
    var overflow = RigidBody3D(MassProperties3D.sphere(1, 1), position=Vec3(1.7e308, 0, 0))
    overflow.linear_velocity = Vec3(large, 0, 0)
    overflow.apply_force(Vec3(1, 0, 0))
    var original = overflow
    with assert_raises(): _ = overflow.integrate(0.25, Vec3(0, 0, 0))
    state_exact(overflow, original)
    var accumulator = RigidBody3D(MassProperties3D.sphere(1, 1))
    accumulator.apply_force(Vec3(large, 0, 0))
    var accumulated = accumulator
    with assert_raises(): accumulator.apply_force(Vec3(large, 0, 0))
    state_exact(accumulator, accumulated)


def main() raises:
    constant_force_and_gravity()
    torque_and_offset_force()
    force_free_sphere()
    accumulation_and_substeps()
    asymmetric_conservation_and_convergence()
    transactional_rejection()
    print("Rigid-body R02a passed: analytic force/torque, force-free conservation, normalized poses, 30/60/120 convergence, accumulator/substep semantics and transactional rejection")
