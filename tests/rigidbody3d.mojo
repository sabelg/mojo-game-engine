"""CPU-only analytic rigid-body mechanics tests; no renderer or physics world."""
from std.testing import assert_equal, assert_true, assert_raises
from mojo_game import MassProperties3D, RigidBody3D, Vec3, Quaternion


def near(a: Float64, b: Float64, tolerance: Float64 = 1e-11) raises:
    assert_true(abs(a - b) <= tolerance)


def vector_near(a: Vec3, b: Vec3, tolerance: Float64 = 1e-11) raises:
    near(a.x, b.x, tolerance)
    near(a.y, b.y, tolerance)
    near(a.z, b.z, tolerance)


def mass_properties() raises:
    # Independent textbook reference values, not a second copy of the formulas.
    var sphere = MassProperties3D.sphere(2, 0.5)
    near(sphere.inverse_mass(), 0.5)
    vector_near(sphere.inertia, Vec3(0.2, 0.2, 0.2))
    var box = MassProperties3D.box(12, Vec3(1, 2, 3))
    vector_near(box.inertia, Vec3(52, 40, 20))
    near(MassProperties3D.fixed().inverse_mass(), 0)
    with assert_raises(): _ = MassProperties3D.sphere(0, 1)
    with assert_raises(): _ = MassProperties3D.sphere(1, -1)
    with assert_raises(): _ = MassProperties3D.box(1, Vec3(1, 0, 1))
    with assert_raises(): _ = MassProperties3D(-1, Vec3(1, 1, 1))
    with assert_raises(): _ = MassProperties3D(0, Vec3(1, 1, 1))
    with assert_raises(): _ = MassProperties3D(1, Vec3(0, 1, 1))
    with assert_raises(): _ = MassProperties3D(1, Vec3(10, 1, 1))


def impulse_and_energy() raises:
    var body = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    body.apply_impulse(Vec3(2, 0, 0))
    vector_near(body.linear_velocity, Vec3(1, 0, 0))
    vector_near(body.angular_velocity, Vec3(0, 0, 0))
    vector_near(body.linear_momentum(), Vec3(2, 0, 0))
    near(body.kinetic_energy(), 1)
    body.apply_angular_impulse(Vec3(0, 0, 1))
    vector_near(body.angular_velocity, Vec3(0, 0, 5))
    vector_near(body.angular_momentum(), Vec3(0, 0, 1))
    near(body.kinetic_energy(), 3.5)
    # A point one metre above COM moves -5 m/s in X from spin, +1 from COM.
    vector_near(body.point_velocity(Vec3(0, 1, 0)), Vec3(-4, 0, 0))
    body.apply_impulse(Vec3(-2, 0, 0))
    body.apply_angular_impulse(Vec3(0, 0, -1))
    near(body.kinetic_energy(), 0)


def offset_and_rotated_inertia() raises:
    var body = RigidBody3D(MassProperties3D.box(12, Vec3(1, 2, 3)))
    body.apply_impulse(Vec3(0, 0, 20), Vec3(0, 1, 0))
    vector_near(body.linear_momentum(), Vec3(0, 0, 20))
    vector_near(body.angular_momentum(), Vec3(20, 0, 0))
    near(body.angular_velocity.x, 20.0 / 52)
    var quarter_turn = Quaternion.axis_angle(Vec3(0, 0, 1), 1.5707963267948966)
    var turned = RigidBody3D(MassProperties3D.box(12, Vec3(1, 2, 3)), orientation=quarter_turn)
    # World X now uses the body's original Y inertia (40), not its X inertia.
    vector_near(turned.inverse_inertia(Vec3(1, 0, 0)), Vec3(0.025, 0, 0))
    turned.apply_angular_impulse(Vec3(40, 0, 0))
    vector_near(turned.angular_velocity, Vec3(1, 0, 0))
    vector_near(turned.angular_momentum(), Vec3(40, 0, 0))
    near(turned.kinetic_energy(), 20)


def pair_momentum() raises:
    var properties = MassProperties3D.box(12, Vec3(1, 2, 3))
    var a = RigidBody3D(properties, position=Vec3(-2, 0, 0))
    var b = RigidBody3D(properties, position=Vec3(2, 0, 0))
    # Equal/opposite impulses at the same physical point preserve total linear
    # and angular momentum, including orbital momentum about the world origin.
    a.apply_impulse(Vec3(0, 0, 1), Vec3(2, 0.5, 0))
    b.apply_impulse(Vec3(0, 0, -1), Vec3(-2, 0.5, 0))
    vector_near(a.linear_momentum() + b.linear_momentum(), Vec3(0, 0, 0))
    var total = a.angular_momentum() + b.angular_momentum()
    total = total + a.position.cross(a.linear_momentum()) + b.position.cross(b.linear_momentum())
    vector_near(total, Vec3(0, 0, 0))


def fixed_and_translation() raises:
    var fixed = RigidBody3D(MassProperties3D.fixed(), position=Vec3(1, 2, 3))
    fixed.apply_impulse(Vec3(1, 2, 3), Vec3(4, 5, 6))
    fixed.apply_angular_impulse(Vec3(1, 2, 3))
    vector_near(fixed.linear_velocity, Vec3(0, 0, 0))
    vector_near(fixed.angular_velocity, Vec3(0, 0, 0))
    vector_near(fixed.position, Vec3(1, 2, 3))
    near(fixed.kinetic_energy(), 0)
    var near_body = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    var far_body = RigidBody3D(MassProperties3D.sphere(2, 0.5), position=Vec3(1e12, -1e12, 1e12))
    for i in range(32):
        var impulse = Vec3(Float64(i % 3) - 1, 0.125, -0.25)
        near_body.apply_impulse(impulse, Vec3(0.25, 0.5, -0.125))
        far_body.apply_impulse(impulse, Vec3(0.25, 0.5, -0.125))
    vector_near(near_body.linear_velocity, far_body.linear_velocity)
    vector_near(near_body.angular_velocity, far_body.angular_velocity)


def replay_and_partition() raises:
    var properties = MassProperties3D.box(12, Vec3(1, 2, 3))
    var one = RigidBody3D(properties)
    var pieces = RigidBody3D(properties)
    one.apply_impulse(Vec3(12, 24, 36), Vec3(0, 0.5, 0))
    # An impulse is instantaneous: partitioning an impulse needs no timestep.
    for _ in range(16): pieces.apply_impulse(Vec3(0.75, 1.5, 2.25), Vec3(0, 0.5, 0))
    vector_near(one.linear_velocity, pieces.linear_velocity)
    vector_near(one.angular_velocity, pieces.angular_velocity)
    var a = RigidBody3D(properties)
    var b = RigidBody3D(properties)
    for i in range(64):
        var impulse = Vec3(Float64(i % 7) / 16, -0.125, 0.25)
        a.apply_impulse(impulse, Vec3(0.5, 0, 0))
        b.apply_impulse(impulse, Vec3(0.5, 0, 0))
    assert_equal(a.linear_velocity.x, b.linear_velocity.x)
    assert_equal(a.linear_velocity.y, b.linear_velocity.y)
    assert_equal(a.linear_velocity.z, b.linear_velocity.z)
    assert_equal(a.angular_velocity.x, b.angular_velocity.x)
    assert_equal(a.angular_velocity.y, b.angular_velocity.y)
    assert_equal(a.angular_velocity.z, b.angular_velocity.z)


def invalid_and_transactional() raises:
    var large = Float64(1e308)
    var infinity = large * large
    var nan = infinity - infinity
    with assert_raises(): _ = MassProperties3D.sphere(nan, 1)
    with assert_raises(): _ = MassProperties3D.sphere(1, infinity)
    with assert_raises(): _ = MassProperties3D.box(1, Vec3(1, nan, 1))
    with assert_raises(): _ = RigidBody3D(MassProperties3D.sphere(1, 1), orientation=Quaternion(0, 0, 0, 0))
    var body = RigidBody3D(MassProperties3D.sphere(2, 0.5))
    body.apply_impulse(Vec3(2, 0, 0))
    var before_linear = body.linear_velocity
    var before_angular = body.angular_velocity
    with assert_raises(): body.apply_impulse(Vec3(nan, 0, 0))
    with assert_raises(): body.apply_impulse(Vec3(0, large, 0), Vec3(large, 0, 0))
    vector_near(body.linear_velocity, before_linear)
    vector_near(body.angular_velocity, before_angular)
    with assert_raises(): body.apply_angular_impulse(Vec3(0, 0, infinity))
    with assert_raises(): _ = body.point_velocity(Vec3(infinity, 0, 0))
    # Scale-normalization accepts a finite quaternion whose naive norm overflows.
    var normalized = RigidBody3D(MassProperties3D.sphere(1, 1), orientation=Quaternion(0, 0, 0, large))
    near(normalized.orientation.w, 1)
    body.properties.mass = -1
    with assert_raises(): body.apply_impulse(Vec3(1, 0, 0))


def main() raises:
    mass_properties()
    impulse_and_energy()
    offset_and_rotated_inertia()
    pair_momentum()
    fixed_and_translation()
    replay_and_partition()
    invalid_and_transactional()
    print("Rigid-body R01 passed: analytic inertia, world-space impulses, energy/momentum, fixed bodies, translation/replay and transactional validation")
