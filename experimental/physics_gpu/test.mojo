"""G01 actual GPU vs unchanged R01/R02a CPU oracle; fixed predeclared gates."""
from std.collections import List
from std.math import sqrt
from std.testing import assert_true, assert_equal, assert_raises
from mojo_game import RigidBody3D, MassProperties3D, Vec3, Quaternion
from experimental.physics_gpu.host import GpuBatch, encode
from experimental.physics_gpu.kernels import STRIDE, FIELDS, WORDS

def near(a: Float64, b: Float64) raises:
    if abs(a - b) > 1e-8 * (1 + abs(b)):
        print("Differential failure:", a, b, "error", abs(a - b))
        raise Error("GPU/CPU component gate failed")

def decoded(raw: List[Float64], i: Int) raises -> RigidBody3D:
    var v = List[Float64]()
    for f in range(FIELDS):
        v.append(raw[f * STRIDE + i + 1])
    var b = RigidBody3D(MassProperties3D(v[0], Vec3(v[1], v[2], v[3])),
        position=Vec3(v[4], v[5], v[6]), orientation=Quaternion(v[7], v[8], v[9], v[10]))
    b.linear_velocity = Vec3(v[11], v[12], v[13])
    b.angular_velocity = Vec3(v[14], v[15], v[16])
    b.force = Vec3(v[17], v[18], v[19])
    b.torque = Vec3(v[20], v[21], v[22])
    return b

def compare(raw: List[Float64], bodies: List[RigidBody3D]) raises -> Vec3:
    var errors = Vec3(0,0,0)
    for i in range(len(bodies)):
        var expected = encode(bodies[i])
        for f in range(FIELDS):
            if f < 7 or f > 10:
                near(raw[f * STRIDE + i + 1], expected[f])
                errors.x = max(errors.x, abs(raw[f * STRIDE + i + 1]-expected[f])/(1+abs(expected[f])))
        var q = Quaternion(raw[7 * STRIDE + i + 1], raw[8 * STRIDE + i + 1],
            raw[9 * STRIDE + i + 1], raw[10 * STRIDE + i + 1])
        var error: Float64 = 0
        for axis in [Vec3(1,0,0), Vec3(0,1,0), Vec3(0,0,1)]:
            error += (q.rotate(axis) - bodies[i].orientation.rotate(axis)).length()
        assert_true(error <= 1e-7)
        errors.y = max(errors.y,error)
        var norm_error = abs(sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w)-1)
        assert_true(norm_error <= 1e-10)
        errors.z = max(errors.z,norm_error)
        if bodies[i].properties.mass == 0:
            for f in range(7):
                assert_equal(raw[f * STRIDE + i + 1], expected[f])
    return errors

def fixture(i: Int) raises -> RigidBody3D:
    var p = MassProperties3D.fixed()
    if i % 5 != 0:
        p = MassProperties3D.sphere(2, .5) if i % 2 == 0 else MassProperties3D.box(12, Vec3(.5,.75,.5))
    var b = RigidBody3D(p, position=Vec3(Float64(i)*2, 3, 0),
        orientation=Quaternion.axis_angle(Vec3(1,2,3), Float64(i)*.02))
    b.apply_impulse(Vec3(.2,.1,0), Vec3(0,.1,0))
    b.apply_force(Vec3(.5,.1,.2), Vec3(.1,0,0))
    return b

def coverage(mut gpu: GpuBatch) raises:
    for count in [0,1,31,32,33,63,64,65,127,128,129,256]:
        var original = List[RigidBody3D]()
        for i in range(count):
            original.append(fixture(i))
        var cpu = original.copy()
        gpu.upload(original)
        assert_equal(gpu.step(1.0/60), 0)
        for i in range(count):
            _ = cpu[i].integrate(1.0/60)
        var first = gpu.raw()
        _ = compare(first, cpu)
        gpu.canaries()
        gpu.upload(original)
        assert_equal(gpu.step(1.0/60), 0)
        var repeated = gpu.raw()
        for i in range(WORDS):
            assert_equal(first[i], repeated[i])
        var reverse = List[RigidBody3D]()
        for i in range(count):
            reverse.append(original[count-1-i])
        gpu.upload(reverse)
        assert_equal(gpu.step(1.0/60), 0)
        var reordered = gpu.raw()
        for i in range(count):
            for f in range(FIELDS):
                assert_equal(reordered[f*STRIDE+i+1], first[f*STRIDE+count-i])
    var boundary = RigidBody3D(MassProperties3D.sphere(2,.5))
    boundary.angular_velocity=Vec3(17.994,23.992,0)
    var boundary_cpu=boundary
    gpu.upload(List[RigidBody3D](length=1,fill=boundary))
    assert_equal(gpu.step(1.0/120,Vec3(0,0,0)),0)
    _=boundary_cpu.integrate(1.0/120,Vec3(0,0,0))
    _ = compare(gpu.raw(),List[RigidBody3D](length=1,fill=boundary_cpu))
    gpu.canaries()
    var too_many = List[RigidBody3D]()
    for i in range(257):
        too_many.append(fixture(i))
    var before = gpu.raw()
    with assert_raises():
        gpu.upload(too_many)
    var after = gpu.raw()
    for i in range(WORDS):
        assert_equal(before[i], after[i])
    print("G01 GPU tail/canary, 0–256 capacity, replay and permutation groups passed")

def rejection(mut gpu: GpuBatch) raises:
    var bodies = List[RigidBody3D]()
    bodies.append(fixture(1))
    bodies.append(fixture(2))
    for mode in range(5):
        gpu.upload(bodies)
        var dt = Float64(1.0/60)
        var ceiling = Float64(1.0/120)
        if mode == 0:
            dt = 0
        elif mode == 1:
            ceiling = 1e-4
        elif mode == 2:
            for f in range(7,11):
                gpu.inject(f,1,0)
        elif mode == 3:
            gpu.inject(14,1,1000)
        else:
            gpu.inject(4,1,1.7e308)
            gpu.inject(11,1,1e308)
            dt = .25
        var before = gpu.raw()
        assert_true(gpu.step(dt, ceiling=ceiling) != 0)
        var after = gpu.raw()
        for i in range(WORDS):
            assert_equal(before[i], after[i])
        gpu.canaries()
    gpu.upload(bodies)
    var saved = gpu.raw()
    var huge = Float64(1e308)
    with assert_raises():
        gpu.forces(Vec3(huge*huge,0,0))
    for invalid_count in [-1,257]:
        gpu.count=invalid_count
        with assert_raises():
            _=gpu.step(1.0/60)
    gpu.count=len(bodies)
    var restored=gpu.raw()
    for i in range(WORDS):
        assert_equal(saved[i],restored[i])
    print("G01 GPU mixed-batch invalid/dt/substep/angular/overflow rollback passed")

def trajectories(mut gpu: GpuBatch) raises:
    for hz in [30,60,120]:
        var dt = 1.0/Float64(hz)
        var cpu = List[RigidBody3D]()
        cpu.append(fixture(1))
        cpu.append(fixture(2))
        cpu.append(fixture(5))
        gpu.upload(cpu)
        for _ in range(hz*2):
            gpu.forces(Vec3(1,0,0), Vec3(0,0,.1))
            assert_equal(gpu.step(dt, ceiling=dt), 0)
            for i in range(len(cpu)):
                cpu[i].force = Vec3(1,0,0)
                cpu[i].torque = Vec3(0,0,.1)
                _ = cpu[i].integrate(dt, max_substep=dt)
        var force_error = compare(gpu.raw(),cpu)
        print("G01 force trajectory hz=",hz," component/frame/norm errors=",force_error.x,",",force_error.y,",",force_error.z,sep="")
        gpu.canaries()
        var asymmetric = RigidBody3D(MassProperties3D.box(12,Vec3(1,2,3)),
            orientation=Quaternion.axis_angle(Vec3(0,1,0),.35))
        asymmetric.angular_velocity = Vec3(.7,1.1,1.5)
        var L = asymmetric.angular_momentum()
        var E = asymmetric.kinetic_energy()
        var oracle = asymmetric
        var one = List[RigidBody3D](length=1, fill=asymmetric)
        gpu.upload(one)
        var max_energy: Float64 = 0
        var errors = Vec3(0,0,0)
        for _ in range(hz*2):
            assert_equal(gpu.step(dt,Vec3(0,0,0),dt),0)
            _ = oracle.integrate(dt,Vec3(0,0,0),max_substep=dt)
            var current = decoded(gpu.raw(),0)
            var delta = current.angular_momentum()-L
            assert_true(max(abs(delta.x),max(abs(delta.y),abs(delta.z))) <= 5e-9)
            max_energy = max(max_energy,abs(current.kinetic_energy()-E)/E)
            var delta_error = compare(gpu.raw(),List[RigidBody3D](length=1, fill=oracle))
            errors.x=max(errors.x,delta_error.x)
            errors.y=max(errors.y,delta_error.y)
            errors.z=max(errors.z,delta_error.z)
        var budget = Float64(2e-4 if hz==30 else (5e-5 if hz==60 else 1.5e-5))
        assert_true(max_energy <= budget)
        print("G01 GPU anisotropic hz=",hz," max_relative_energy=",max_energy," component/frame/norm errors=",errors.x,",",errors.y,",",errors.z,sep="")
    print("G01 GPU 2-second 30/60/120 force/torque/gravity and anisotropic oracle gates passed")

def main() raises:
    var gpu = GpuBatch()
    print("Actual physics GPU:",gpu.device(),"precision Float64; explicit buffers < 16 MiB")
    coverage(gpu)
    rejection(gpu)
    trajectories(gpu)
    print("G01 GPU differential qualification passed; no contacts, friction, joints or CCD")
