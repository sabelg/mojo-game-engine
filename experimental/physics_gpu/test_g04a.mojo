"""G04a actual GPU response against independent matrix reference and analytic laws."""
from std.collections import List
from std.testing import assert_equal,assert_true,assert_raises
from std.memory import Pointer
from std.ffi import external_call
from std.math import sqrt
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.collision import SphereCommand,BoxCommand,ShapeHandle
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import OracleBox,matrix,apply,oracle_box_contact
from experimental.physics_gpu.boundary_reference import legacy_separation
from experimental.physics_gpu.shape_kernels import sphere_box
from experimental.physics_gpu.normal_response import GpuNormalResponse
from experimental.physics_gpu.response_reference import ResponseReference,ReferenceResult,energy
from experimental.physics_gpu.kernels import STRIDE,FIELDS

def near(a: Float64,b: Float64) raises:
    assert_true(abs(a-b)<=1e-8*(1+abs(b)))
def geometric(a: Float64,b: Float64) raises:
    assert_true(abs(a-b)<=1e-9+1e-12*abs(b))
def vector(a: Vec3,b: Vec3) raises:
    near(a.x,b.x);near(a.y,b.y);near(a.z,b.z)
def decoded(values: List[Float64],slot: Int) raises -> RigidBody3D:
    var m=MassProperties3D(values[slot+1],Vec3(values[STRIDE+slot+1],values[2*STRIDE+slot+1],values[3*STRIDE+slot+1]))
    var b=RigidBody3D(m,Vec3(values[4*STRIDE+slot+1],values[5*STRIDE+slot+1],values[6*STRIDE+slot+1]),Quaternion(values[7*STRIDE+slot+1],values[8*STRIDE+slot+1],values[9*STRIDE+slot+1],values[10*STRIDE+slot+1]))
    b.linear_velocity=Vec3(values[11*STRIDE+slot+1],values[12*STRIDE+slot+1],values[13*STRIDE+slot+1])
    b.angular_velocity=Vec3(values[14*STRIDE+slot+1],values[15*STRIDE+slot+1],values[16*STRIDE+slot+1])
    b.force=Vec3(values[17*STRIDE+slot+1],values[18*STRIDE+slot+1],values[19*STRIDE+slot+1]);b.torque=Vec3(values[20*STRIDE+slot+1],values[21*STRIDE+slot+1],values[22*STRIDE+slot+1]);return b
def compare(mut r: GpuNormalResponse,result: ReferenceResult) raises:
    var raw=r.history.world.bodies.raw()
    for i in range(len(result.bodies)):
        var a=decoded(raw,result.slots[i]);var b=result.bodies[i]
        geometric(a.position.x,b.position.x);geometric(a.position.y,b.position.y);geometric(a.position.z,b.position.z)
        vector(a.linear_velocity,b.linear_velocity);vector(a.angular_velocity,b.angular_velocity);vector(a.force,b.force);vector(a.torque,b.torque)
        near(a.orientation.x,b.orientation.x);near(a.orientation.y,b.orientation.y);near(a.orientation.z,b.orientation.z);near(a.orientation.w,b.orientation.w)
        var q=a.orientation;assert_true(abs(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w-1)<=1e-10)
    for f in range(FIELDS):
        assert_equal(raw[f*STRIDE],Float64(-987654321.25));assert_equal(raw[f*STRIDE+STRIDE-1],Float64(-987654321.25))
def add_sphere(mut r: GpuNormalResponse,b: RigidBody3D,radius: Float64=.5) raises -> OracleSphere:
    var handles=r.history.world.bodies.submit([BodyCommand.create(b)]);var shapes=r.history.world.submit_shapes([SphereCommand.attach(handles[0],radius)])
    return OracleSphere(shapes[0],handles[0],1,b,radius,Vec3(0,0,0))
def add_box(mut r: GpuNormalResponse,b: RigidBody3D,half: Vec3=Vec3(1,1,1),local: Quaternion=Quaternion()) raises -> OracleBox:
    var handles=r.history.world.bodies.submit([BodyCommand.create(b)]);var shapes=r.history.world.submit_boxes([BoxCommand.attach(handles[0],half,orientation=local)])
    return OracleBox(shapes[0],handles[0],1,b,half,Vec3(0,0,0),local)
def sphere(p: Vec3,m: Float64=1,radius: Float64=.5,v: Vec3=Vec3(0,0,0)) raises -> RigidBody3D:
    var b=RigidBody3D(MassProperties3D.sphere(m,radius),position=p);b.linear_velocity=v;return b
def fixed(p: Vec3=Vec3(0,0,0)) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.fixed(),position=p)
def momentum(bodies: List[RigidBody3D]) raises -> Vec3:
    var p=Vec3(0,0,0)
    for b in bodies:p=p+b.linear_momentum()
    return p
def angular(bodies: List[RigidBody3D]) raises -> Vec3:
    var p=Vec3(0,0,0)
    for b in bodies:p=p+b.position.cross(b.linear_momentum())+b.angular_momentum()
    return p
def reject(mut r: GpuNormalResponse,code: Int32,dt: Float64=1.0/60,e: Float64=0,vi: Int32=32,pi: Int32=32,prepared: Bool=False,count: Int32=0) raises:
    var before=r.history.world.bodies.raw();var meta=r.history.world.bodies.metadata();var cache=r.history.debug_cache();var returned=False
    with assert_raises():
        if prepared:_=r._solve_prepared(count,dt,e,vi,pi)
        else:_=r.resolve(dt,e,vi,pi)
        returned=True
    assert_true(not returned);assert_equal(r.last_error,code)
    var after=r.history.world.bodies.raw();var after_meta=r.history.world.bodies.metadata();var after_cache=r.history.debug_cache()
    for i in range(len(before)):assert_equal(before[i],after[i])
    for i in range(len(meta)):assert_equal(meta[i],after_meta[i])
    for i in range(len(cache[0])):assert_equal(cache[0][i],after_cache[0][i])
    for i in range(len(cache[1])):assert_equal(cache[1][i],after_cache[1][i])
    for i in range(5):assert_equal(cache[2][i],after_cache[2][i])

def centered_impacts() raises:
    for e in [0.0,.5,1.0]:
        for dt in [1.0/30,1.0/60,1.0/120,1.0/240]:
            var r=GpuNormalResponse();var reference=ResponseReference();var spheres: List[OracleSphere]=[add_sphere(r,sphere(Vec3(0,0,0),2,v=Vec3(2,0,0))),add_sphere(r,sphere(Vec3(1,0,0),3,v=Vec3(-1,0,0)))];var boxes=List[OracleBox]()
            var expected=reference.solve(spheres,boxes,dt,e);var report=r.resolve(dt,e);compare(r,expected)
            var raw=r.history.world.bodies.raw();var a=decoded(raw,0);var b=decoded(raw,1);var j=(1+e)*3/(.5+1.0/3)
            near(a.linear_velocity.x,2-j/2);near(b.linear_velocity.x,-1+j/3);near(b.linear_velocity.x-a.linear_velocity.x,e*3)
            near(a.linear_momentum().x+b.linear_momentum().x,Float64(1));near(report.energy_before,Float64(5.5));near(report.energy_after,5.5-(1-e*e)*9/(2*(.5+1.0/3)))
            assert_true(report.penetration<=1e-5+1e-9);r.close()
    var r=GpuNormalResponse();var reference=ResponseReference();var spheres: List[OracleSphere]=[add_sphere(r,sphere(Vec3(0,0,0),v=Vec3(.1,0,0))),add_sphere(r,sphere(Vec3(1,0,0)))];var none=List[OracleBox]()
    var expected=reference.solve(spheres,none,1.0/60,1);_=r.resolve(1.0/60,1);compare(r,expected);near(decoded(r.history.world.bodies.raw(),0).linear_velocity.x,.05);r.close()
    print("G04a GPU centered unequal-mass impacts, restitution/energy/momentum laws, low-speed threshold and dt invariance passed")

def fixed_and_separating() raises:
    for e in [0.0,1.0]:
        var r=GpuNormalResponse();var reference=ResponseReference();var boxes: List[OracleBox]=[add_box(r,fixed())];var spheres: List[OracleSphere]=[add_sphere(r,sphere(Vec3(1.5,0,0),v=Vec3(-1,0,0)))];var before=r.history.world.bodies.raw()
        var expected=reference.solve(spheres,boxes,1.0/60,e);_=r.resolve(1.0/60,e);compare(r,expected)
        var raw=r.history.world.bodies.raw();near(decoded(raw,1).linear_velocity.x,e)
        for f in range(FIELDS):assert_equal(raw[f*STRIDE+1],before[f*STRIDE+1])
        var again=r.resolve(1.0/60,e);near(decoded(r.history.world.bodies.raw(),1).linear_velocity.x,e);near(r.impulses()[1],Float64(0));r.close()
    var r=GpuNormalResponse();var reference=ResponseReference();var spheres: List[OracleSphere]=[add_sphere(r,sphere(Vec3(0,0,0),v=Vec3(-1,0,0))),add_sphere(r,sphere(Vec3(.9,0,0),v=Vec3(1,0,0)))];var none=List[OracleBox]()
    var expected=reference.solve(spheres,none,1.0/60,1);_=r.resolve(1.0/60,1);compare(r,expected);near(r.impulses()[1],Float64(0));r.close()
    var fixed_pair=GpuNormalResponse();_=add_sphere(fixed_pair,fixed(),1);_=add_sphere(fixed_pair,fixed(),1)
    var before=fixed_pair.history.world.bodies.raw();var report=fixed_pair.resolve(1.0/60,1);assert_equal(report.fixed_pairs,Int32(1));var after=fixed_pair.history.world.bodies.raw()
    for i in range(len(before)):assert_equal(before[i],after[i])
    fixed_pair.close();print("G04a GPU fixed-body reflection, fixed/fixed no-op, separating overlap and cold repeated resolves passed")

def off_center_and_metamorphic() raises:
    for rotated in range(2):
        for reversed in range(2):
            var r=GpuNormalResponse();var reference=ResponseReference();var bodies: List[RigidBody3D]=[]
            var a=sphere(Vec3(1.4999 if rotated else 1.5,.5,0),2,v=Vec3(-1,0,0));var box=RigidBody3D(MassProperties3D(3,Vec3(1,1.5,2)),orientation=Quaternion(0,1,0,1) if rotated else Quaternion());var local=Quaternion(0,-1,0,1) if rotated else Quaternion()
            var spheres=List[OracleSphere]();var boxes=List[OracleBox]()
            if reversed:boxes.append(add_box(r,box,local=local))
            spheres.append(add_sphere(r,a))
            if not reversed:boxes.append(add_box(r,box,local=local))
            bodies.append(a);bodies.append(box);var initial_p=momentum(bodies);var initial_l=angular(bodies)
            var expected=reference.solve(spheres,boxes,1.0/60,.5);var diagnostic=r.resolve(1.0/60,.5)
            compare(r,expected)
            var raw=r.history.world.bodies.raw();var actual_a=decoded(raw,Int(spheres[0].body_handle.slot));var actual_b=decoded(raw,Int(boxes[0].body_handle.slot))
            var inv_z=Float64(1.0 if rotated else .5);var k=.5+1.0/3+.25*inv_z;var j=1.5/k
            near(actual_a.linear_velocity.x,-1+j/2);near(actual_b.linear_velocity.x,-j/3);near(actual_b.angular_velocity.z,.5*j*inv_z)
            var final: List[RigidBody3D]=[actual_a,actual_b];vector(momentum(final),initial_p);vector(angular(final),initial_l)
            near(actual_a.kinetic_energy()+actual_b.kinetic_energy(),1-.75/(2*k));r.close()
    var transform=Quaternion.axis_angle(Vec3(1,2,3),.6);var rotation=matrix(transform);var translation=Vec3(3,-2,1)
    var r=GpuNormalResponse();var reference=ResponseReference();var a=sphere(apply(rotation,Vec3(1.4999,.5,0))+translation,2,v=apply(rotation,Vec3(-1,0,0)))
    a.orientation=transform*a.orientation;var b=RigidBody3D(MassProperties3D(3,Vec3(1,1.5,2)),position=translation,orientation=transform)
    var spheres: List[OracleSphere]=[add_sphere(r,a)];var boxes: List[OracleBox]=[add_box(r,b)]
    var expected=reference.solve(spheres,boxes,1.0/60,.5);var diagnostic=r.resolve(1.0/60,.5);compare(r,expected)
    var raw=r.history.world.bodies.raw();var j=1.5/(.5+1.0/3+.125)
    vector(decoded(raw,0).linear_velocity,apply(rotation,Vec3(-1+j/2,0,0)));vector(decoded(raw,1).angular_velocity,apply(rotation,Vec3(0,0,.25*j)));r.close()
    print("G04a GPU off-center angular/effective-mass response, rotated inertia, closed angular momentum, slot reversal and rigid-transform checks passed")

def shared_body_and_penetration() raises:
    var r=GpuNormalResponse();var reference=ResponseReference();var spheres=List[OracleSphere]();var none=List[OracleBox]()
    for i in range(3):spheres.append(add_sphere(r,sphere(Vec3(Float64(i),0,0),v=Vec3(1.0 if i==0 else 0.0,0,0))))
    var expected=reference.solve(spheres,none,1.0/60,0);var report=r.resolve(1.0/60);compare(r,expected)
    var raw=r.history.world.bodies.raw()
    for i in range(3):near(decoded(raw,i).linear_velocity.x,1.0/3)
    near(report.energy_after,1.0/6);r.close()
    var recovery=GpuNormalResponse();var cr=ResponseReference();var overlap=List[OracleSphere]()
    for i in range(3):overlap.append(add_sphere(recovery,sphere(Vec3(Float64(i)*.9,0,0))))
    var positions=cr.solve(overlap,none,1.0/60,0);var projected=recovery.resolve(1.0/60);compare(recovery,positions)
    raw=recovery.history.world.bodies.raw();geometric(decoded(raw,0).position.x,-.09999);geometric(decoded(raw,1).position.x,.9);geometric(decoded(raw,2).position.x,1.89999)
    near(projected.energy_before,Float64(0));near(projected.energy_after,Float64(0));assert_true(projected.penetration<=1e-5+1e-9);recovery.close()
    print("G04a GPU shared-body serial convergence, inelastic chain energy and unbiased shallow penetration recovery passed")

def timestep_support() raises:
    for hz in [30,60,120,240]:
        var r=GpuNormalResponse();var reference=ResponseReference();var floor=add_box(r,fixed(Vec3(0,-.1,0)),Vec3(2,.1,2));var b=sphere(Vec3(0,.25,0),radius=.25)
        var spheres: List[OracleSphere]=[add_sphere(r,b,.25)];var boxes: List[OracleBox]=[floor];var dt=1.0/Float64(hz)
        for _ in range(hz):
            assert_equal(r.history.world.bodies.step(dt),0);_=spheres[0].body.integrate(dt)
            var expected=reference.solve(spheres,boxes,dt,0);_=r.resolve(dt);compare(r,expected)
            for i in range(len(expected.bodies)):
                if expected.slots[i]==Int(spheres[0].body_handle.slot):spheres[0].body=expected.bodies[i]
        var actual=decoded(r.history.world.bodies.raw(),1);geometric(actual.position.y,.25-1e-5);near(actual.linear_velocity.y,Float64(0));r.close()
    print("G04a GPU one-second resting support and reference trajectories at 30/60/120/240 Hz passed")

def oblique_and_guard_boundaries() raises:
    var r=GpuNormalResponse();var reference=ResponseReference();var q=Quaternion.axis_angle(Vec3(0,0,1),.4);var axes=matrix(q)
    var b=RigidBody3D(MassProperties3D.fixed(),orientation=q)
    var boxes: List[OracleBox]=[add_box(r,b)];var initial=sphere(apply(axes,Vec3(1.4999,.5,0)),v=apply(axes,Vec3(-1,.4,0)))
    initial.force=Vec3(.1,.2,.3);initial.torque=Vec3(.01,.02,.03)
    var spheres: List[OracleSphere]=[add_sphere(r,initial)];var before=r.history.world.bodies.raw()
    var expected=reference.solve(spheres,boxes,1.0/60,.5);_=r.resolve(1.0/60,.5);compare(r,expected)
    var raw=r.history.world.bodies.raw();vector(decoded(raw,1).linear_velocity,apply(axes,Vec3(.5,.4,0)))
    for f in range(17,23):assert_equal(before[f*STRIDE+2],raw[f*STRIDE+2])
    r.close()
    var none=List[OracleBox]();var overlap=GpuNormalResponse();var os=List[OracleSphere]()
    for i in range(4):os.append(add_sphere(overlap,sphere(Vec3(Float64(i)*.8,0,0))))
    reject(overlap,59)
    with assert_raises():_=reference.solve(os,none,1.0/60,0)
    assert_equal(reference.last_error,Int32(59));overlap.close()
    var new_contact=GpuNormalResponse();var ns: List[OracleSphere]=[add_sphere(new_contact,sphere(Vec3(0,0,0))),add_sphere(new_contact,sphere(Vec3(.9,0,0))),add_sphere(new_contact,sphere(Vec3(1.91,0,0)))]
    reject(new_contact,60)
    with assert_raises():_=reference.solve(ns,none,1.0/60,0)
    assert_equal(reference.last_error,Int32(60));new_contact.close()
    var trapped=GpuNormalResponse();var walls: List[OracleBox]=[add_box(trapped,fixed(Vec3(-.55,0,0)),Vec3(.1,1,1)),add_box(trapped,fixed(Vec3(.55,0,0)),Vec3(.1,1,1))]
    var sphere_list: List[OracleSphere]=[add_sphere(trapped,sphere(Vec3(0,0,0)))]
    reject(trapped,58)
    with assert_raises():_=reference.solve(sphere_list,walls,1.0/60,0)
    assert_equal(reference.last_error,Int32(58));trapped.close()
    print("G04a GPU oblique frictionless response/force preservation and projection/new-contact/incompatible-wall guard boundaries passed")

def corrupt_contact(headers: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],mode: Int32):
    if mode==0:headers[unsafe_offset=2]+=1
    else:
        var huge=Float64(1e308);values[unsafe_offset=1]=huge*huge-huge*huge

def failure_semantics() raises:
    var r=GpuNormalResponse();var reference=ResponseReference();var spheres: List[OracleSphere]=[add_sphere(r,sphere(Vec3(0,0,0))),add_sphere(r,sphere(Vec3(1,0,0)))];var none=List[OracleBox]()
    _=r.history.world.bodies.submit([BodyCommand.force(spheres[0].body_handle,Vec3(.1,.2,.3),Vec3(.01,.02,.03))])
    var huge=Float64(1e308);var nan=huge*huge-huge*huge
    for dt in [Float64(0),Float64(1.0/1000),Float64(.1),nan]:reject(r,51,dt)
    for e in [Float64(-.1),Float64(1.1),nan]:reject(r,51,e=e)
    reject(r,51,vi=0);reject(r,51,pi=65)
    for mode in range(2):
        var count=r.history.world._detect_on_device()
        r.history.world.bodies._ctx.enqueue_function[corrupt_contact](r.history.world._contact_out,r.history.world._contact_values,Int32(mode),grid_dim=1,block_dim=1);r.history.world.bodies._ctx.synchronize()
        reject(r,Int32(53 if mode==0 else 54),prepared=True,count=Int32(count[1]))
    var count=r.history.world._detect_on_device();spheres[1].body.position.x=1.1;_=r.history.world.bodies.submit([BodyCommand.update(spheres[1].body_handle,spheres[1].body)])
    reject(r,53,prepared=True,count=Int32(count[1]));r.close()
    var capacity=GpuNormalResponse(0);_=add_sphere(capacity,sphere(Vec3(0,0,0)));_=add_sphere(capacity,sphere(Vec3(1,0,0)));reject(capacity,50);capacity.close()
    var many=GpuNormalResponse()
    for _ in range(12):_=add_sphere(many,sphere(Vec3(0,0,0),radius=.1),.1)
    reject(many,50);many.close()
    var profile=GpuNormalResponse();_=add_sphere(profile,sphere(Vec3(0,0,0),.01));_=add_sphere(profile,sphere(Vec3(1,0,0)));reject(profile,52);profile.close()
    var deep=GpuNormalResponse();_=add_sphere(deep,sphere(Vec3(0,0,0)));_=add_sphere(deep,sphere(Vec3(.7,0,0)));reject(deep,57);deep.close()
    var chain=GpuNormalResponse();var cs=List[OracleSphere]()
    for i in range(3):cs.append(add_sphere(chain,sphere(Vec3(Float64(i),0,0),v=Vec3(1.0 if i==0 else 0.0,0,0))))
    reject(chain,55,vi=1)
    with assert_raises():_=reference.solve(cs,none,1.0/60,0,vi=1)
    assert_equal(reference.last_error,Int32(55));chain.close()
    var position=GpuNormalResponse();var ps=List[OracleSphere]()
    for i in range(3):ps.append(add_sphere(position,sphere(Vec3(Float64(i)*.9,0,0))))
    reject(position,58,pi=1)
    with assert_raises():_=reference.solve(ps,none,1.0/60,0,pi=1)
    assert_equal(reference.last_error,Int32(58));position.close()
    var energetic=GpuNormalResponse();var es=List[OracleSphere]()
    for i in range(3):es.append(add_sphere(energetic,sphere(Vec3(Float64(i),0,0),v=Vec3(.5 if i==0 else 1.0 if i==1 else 0.0,0,0))))
    reject(energetic,56,e=1)
    with assert_raises():_=reference.solve(es,none,1.0/60,1)
    assert_equal(reference.last_error,Int32(56));energetic.close()
    print("G04a GPU invalid/range/capacity/stale/corrupt/convergence/depth and coupled restitution energy failures preserve body/force/history state passed")

def exact_bits(value: Float64) -> UInt64:
    var copy=Float64(value);var output=UInt64(0)
    _=external_call["memcpy",Pointer[UInt8,MutAnyOrigin]](Pointer(to=output),Pointer(to=copy),UInt64(8))
    return output

def probe_box_separation(bounds: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin],sphere: Int32,box: Int32):
    var result=sphere_box(bounds,Int(sphere),Int(box));output[unsafe_offset=0]=result.separation

def rotated_boundary_regression() raises:
    # Original exact construction: body +Y quarter-turn and local inverse.
    # Their real normalized composition is identity. The rational CPU matrix
    # now preserves this structural identity rather than losing orthogonality.
    var ulp=Float64(2.220446049250313e-16)
    with open("build/physics-g04a/boundary-last.jsonl","w") as file:
        for rotated in range(2):
            for delta in [Float64(-1e-8),Float64(-1e-12),-ulp,Float64(0),ulp,Float64(1e-12),Float64(1e-8)]:
                for direction in [Float64(-1),Float64(1)]:
                    var x=Float64(1.5)+delta;var r=GpuNormalResponse();var reference=ResponseReference()
                    var box=RigidBody3D(MassProperties3D(3,Vec3(1,1.5,2)),orientation=Quaternion(0,1,0,1) if rotated else Quaternion())
                    var s=add_sphere(r,sphere(Vec3(x,.5,0),2,v=Vec3(direction,0,0)))
                    var b=add_box(r,box,local=Quaternion(0,-1,0,1) if rotated else Quaternion())
                    var spheres: List[OracleSphere]=[s];var boxes: List[OracleBox]=[b]
                    var cpu=oracle_box_contact(s,b);var legacy=legacy_separation(s,b)
                    var counts=r.history.world._detect_on_device()
                    var buffer=r.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](1)
                    r.history.world.bodies._ctx.enqueue_function[probe_box_separation](r.history.world._bounds,buffer,s.shape.slot,b.shape.slot,grid_dim=1,block_dim=1)
                    r.history.world.bodies._ctx.synchronize();var gpu=Float64(0)
                    with buffer.map_to_host() as values:gpu=Float64(values[0])
                    var body_values=r.history.world.bodies.raw()
                    assert_equal(gpu,x-1.5);assert_equal(cpu.separation,x-1.5)
                    assert_equal(counts[1],1 if delta<=0 else 0)
                    var expected=reference.solve(spheres,boxes,1.0/60,.5)
                    var report=r.resolve(1.0/60,.5);compare(r,expected)
                    var actual=r.history.world.bodies.raw();var impulse=r.impulses()[1] if counts[1] else Float64(0)
                    assert_true(impulse>=0)
                    if direction>0 or delta>0:
                        near(decoded(actual,0).linear_velocity.x,direction);near(impulse,Float64(0))
                    else:
                        var j=1.5/(.5+1.0/3+(.25 if rotated else .125))
                        near(decoded(actual,0).linear_velocity.x,-1+j/2)
                        assert_equal(report.contacts,Int32(1))
                    if delta==0:
                        assert_equal(gpu,Float64(0));assert_equal(cpu.separation,Float64(0))
                    file.write('{"rotated":'+String(rotated)+',"sphere_x_bits":'+String(exact_bits(x))+',"delta_bits":'+String(exact_bits(delta))+',"direction_bits":'+String(exact_bits(direction))+',"cpu_input_qy_bits":'+String(exact_bits(box.orientation.y))+',"cpu_input_qw_bits":'+String(exact_bits(box.orientation.w))+',"GPU_stored_box_qy_bits":'+String(exact_bits(body_values[8*STRIDE+2]))+',"GPU_stored_box_qw_bits":'+String(exact_bits(body_values[10*STRIDE+2]))+',"legacy_CPU_separation_bits":'+String(exact_bits(legacy))+',"CPU_separation_bits":'+String(exact_bits(cpu.separation))+',"GPU_separation_bits":'+String(exact_bits(gpu))+',"GPU_contacts":'+String(counts[1])+',"CPU_contacts":'+String(1 if cpu.separation<=0 else 0)+',"legacy_CPU_contacts":'+String(1 if legacy<=0 else 0)+',"normal_impulse_bits":'+String(exact_bits(impulse))+'}\n')
                    r.close()
    print("G04a original rotated exact tangency and signed one-ULP/near boundaries: CPU/GPU agree, exact bit records, zero-depth response and no attractive impulses passed")

def main() raises:
    rotated_boundary_regression();centered_impacts();fixed_and_separating();off_center_and_metamorphic();shared_body_and_penetration();timestep_support();oblique_and_guard_boundaries();failure_semantics()
    print("G04a actual GPU normal-response proof qualified; serial bounded solver, no friction or warm start")
