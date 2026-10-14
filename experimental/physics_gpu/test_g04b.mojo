"""Actual GPU friction, independent spectral/KKT CPU oracle and closed laws."""
from std.collections import List
from std.math import sqrt,cos,sin
from std.memory import Pointer
from experimental.physics_gpu.friction_kernels import disk_min
from experimental.physics_gpu.friction_reference import spectral_min
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.friction_response import GpuFrictionResponse,FrictionReport
from experimental.physics_gpu.friction_reference import FrictionReference,FrictionResult
from experimental.physics_gpu.response_reference import ReferenceResult
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import OracleBox,matrix,apply,mixed_frame
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.test_g04a import near,geometric,vector,decoded,compare,add_sphere,add_box,sphere,fixed,momentum,angular,rotated_boundary_regression,corrupt_contact

def compare_friction(mut r: GpuFrictionResponse,result: FrictionResult) raises:
    var normal=ReferenceResult(result.bodies.copy(),result.slots.copy(),result.report.normal);compare(r.normal,normal)
def cone(mut r: GpuFrictionResponse,report: FrictionReport) raises:
    var normal=r.normal.impulses();var tangents=r.tangents()
    for i in range(Int(report.normal.contacts)):
        assert_true(normal[i+1]>=0)
        var length=sqrt(tangents[1+i*2]**2+tangents[2+i*2]**2)
        assert_true(length<=report.coefficient*normal[i+1]+1e-12*(1+report.coefficient*normal[i+1]))
    assert_true(report.normal.energy_after<=report.normal.energy_before+1e-9*(1+report.normal.energy_before))
def reject(mut r: GpuFrictionResponse,code: Int32,mu: Float64=.4,vi: Int32=32,prepared: Bool=False,count: Int32=0,e: Float64=0) raises:
    var before=r.normal.history.world.bodies.raw();var meta=r.normal.history.world.bodies.metadata();var cache=r.normal.history.debug_cache();var returned=False
    with assert_raises():
        if prepared:_=r._solve_prepared(count,1.0/60,e,vi,32,mu)
        else:_=r.resolve(1.0/60,restitution=e,coefficient=mu,velocity_iterations=vi)
        returned=True
    assert_true(not returned);assert_equal(r.normal.last_error,code)
    var after=r.normal.history.world.bodies.raw();var after_meta=r.normal.history.world.bodies.metadata();var after_cache=r.normal.history.debug_cache()
    for i in range(len(before)):assert_equal(before[i],after[i])
    for i in range(len(meta)):assert_equal(meta[i],after_meta[i])
    for i in range(len(cache[0])):assert_equal(cache[0][i],after_cache[0][i])
    for i in range(len(cache[1])):assert_equal(cache[1][i],after_cache[1][i])
    for i in range(5):assert_equal(cache[2][i],after_cache[2][i])


def disk_probe(output: Pointer[Float64,MutAnyOrigin],kx: Float64,ky: Float64,kz: Float64,ux: Float64,uy: Float64,radius: Float64):
    var j=disk_min(Vec3(kx,ky,kz),Vec3(ux,uy,0),radius);output[unsafe_offset=1]=j.x;output[unsafe_offset=2]=j.y;output[unsafe_offset=3]=j.z

def independent_block_laws() raises:
    var r=GpuFrictionResponse();var buffer=r.normal.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](5)
    for angle in [Float64(0),Float64(.37),Float64(1.1)]:
        var c=cos(angle);var s=sin(angle);var k=Vec3(2*c*c+5*s*s,(2-5)*c*s,2*s*s+5*c*c)
        for constrained in range(2):
            var target=Vec3(.3,-.4,0) if constrained else Vec3(.1,-.2,0);var eta=Float64(7 if constrained else 0)
            var u=Vec3(-(2+eta)*target.x,-(5+eta)*target.y,0)
            var expected=Vec3(c*target.x-s*target.y,s*target.x+c*target.y,eta);u=Vec3(c*u.x-s*u.y,s*u.x+c*u.y,0)
            buffer.enqueue_fill(Float64(-1234567))
            r.normal.history.world.bodies._ctx.enqueue_function[disk_probe](buffer,k.x,k.y,k.z,u.x,u.y,Float64(.5),grid_dim=1,block_dim=1);r.normal.history.world.bodies._ctx.synchronize()
            with buffer.map_to_host() as data:
                near(Float64(data[1]),expected.x);near(Float64(data[2]),expected.y);near(Float64(data[3]),eta)
                assert_equal(Float64(data[0]),Float64(-1234567));assert_equal(Float64(data[4]),Float64(-1234567))
            var cpu=spectral_min(k,u,.5);vector(cpu,expected)
    r.close();print("G04b independently constructed anisotropic disk/KKT exact solutions and rotated basis laws passed")

def analytic_sliding() raises:
    for mu in [Float64(0),Float64(.1),Float64(1),Float64(2)]:
        for restitution in [Float64(0),Float64(.5),Float64(1)]:
            for angle in [Float64(0),Float64(.37),Float64(1.1)]:
                var r=GpuFrictionResponse(basis_angle=angle);var reference=FrictionReference()
                var spheres: List[OracleSphere]=[add_sphere(r.normal,sphere(Vec3(0,.5,0),v=Vec3(2,-1,0)))];var boxes: List[OracleBox]=[add_box(r.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))]
                var expected=reference.solve(spheres,boxes,1.0/60,restitution,mu=mu);var report=r.resolve(1.0/60,restitution,mu);compare_friction(r,expected);cone(r,report)
                var actual=decoded(r.normal.history.world.bodies.raw(),0);var j=min(2/3.5,mu*(1+restitution))
                near(actual.linear_velocity.x,2-j);near(actual.linear_velocity.y,restitution);near(actual.angular_velocity.z,-5*j)
                near(report.normal.energy_after,.5*((2-j)**2+restitution*restitution)+.05*(5*j)**2)
                near(r.normal.impulses()[1],1+restitution)
                if mu>=1:near(actual.linear_velocity.x+.5*actual.angular_velocity.z,Float64(0))
                elif mu>0:assert_true(actual.linear_velocity.x+.5*actual.angular_velocity.z>0)
                r.close()
    for speed in [Float64(0),Float64(1e-12),Float64(1e-8)]:
        var r=GpuFrictionResponse();_=add_sphere(r.normal,sphere(Vec3(0,.5,0),v=Vec3(speed,-1,0)));_=add_box(r.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))
        var report=r.resolve(1.0/60,coefficient=.8);cone(r,report);var a=decoded(r.normal.history.world.bodies.raw(),0)
        near(a.linear_velocity.x,speed*5/7);near(a.angular_velocity.z,-speed*10/7);r.close()
    var cold=GpuFrictionResponse();_=add_sphere(cold.normal,sphere(Vec3(0,.5,0),v=Vec3(2,-1,0)));_=add_box(cold.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))
    _=cold.resolve(1.0/60,coefficient=.1);var before=cold.normal.history.world.bodies.raw();var report=cold.resolve(1.0/60,coefficient=.1);var after=cold.normal.history.world.bodies.raw()
    for i in range(len(before)):assert_equal(before[i],after[i])
    near(cold.normal.impulses()[1],Float64(0));near(report.maximum_tangent_impulse,Float64(0));cold.close()
    var separating=GpuFrictionResponse();_=add_sphere(separating.normal,sphere(Vec3(0,.5,0),v=Vec3(2,1,0)));_=add_box(separating.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))
    var separated_report=separating.resolve(1.0/60,coefficient=2);near(decoded(separating.normal.history.world.bodies.raw(),0).linear_velocity.x,Float64(2));near(separated_report.maximum_tangent_impulse,Float64(0));separating.close()
    print("G04b analytic circular-cone sliding/stick, energy loss, restitution, tangent-basis invariance and near-zero speed passed")

def zero_equivalence() raises:
    from experimental.physics_gpu.normal_response import GpuNormalResponse
    for dt in [Float64(1.0/30),Float64(1.0/60),Float64(1.0/120),Float64(1.0/240)]:
        var f=GpuFrictionResponse();var n=GpuNormalResponse()
        for i in range(3):
            var b=sphere(Vec3(Float64(i),0,0),v=Vec3(1.0 if i==0 else 0.0,.3,-.2));_=add_sphere(f.normal,b);_=add_sphere(n,b)
        var a=f.resolve(dt,coefficient=0);var b=n.resolve(dt);var fa=f.normal.history.world.bodies.raw();var nb=n.history.world.bodies.raw()
        for i in range(len(fa)):assert_equal(fa[i],nb[i])
        assert_equal(a.normal.energy_after,b.energy_after);assert_equal(a.normal.velocity_residual,b.velocity_residual);assert_equal(a.normal.velocity_iterations,b.velocity_iterations)
        var jt=f.tangents()
        for value in jt:assert_equal(value,Float64(0))
        f.close();n.close()
    print("G04b zero-friction body bytes and original G04a report equivalence at four timesteps passed")

def inclined_support() raises:
    var q=Quaternion.axis_angle(Vec3(0,0,1),.3);var rotation=matrix(q);var up=apply(rotation,Vec3(0,1,0));var tangent=apply(rotation,Vec3(1,0,0))
    for hz in [30,60,120,240]:
        for mu in [Float64(.02),Float64(.6)]:
            var dt=1.0/Float64(hz);var r=GpuFrictionResponse();var reference=FrictionReference()
            var b=sphere(up*(.5-1e-4),v=Vec3(0,-9.81*dt,0));var floor=RigidBody3D(MassProperties3D.fixed(),position=up*(-.1),orientation=q)
            var spheres: List[OracleSphere]=[add_sphere(r.normal,b)];var boxes: List[OracleBox]=[add_box(r.normal,floor,Vec3(5,.1,5))]
            var frame=mixed_frame(spheres,boxes);assert_equal(len(frame.contacts),1);var p=frame.contacts[0].witness_a*.5+frame.contacts[0].witness_b*.5
            var lever=(p-b.position).length();var k=1+lever*lever/.1;var normal_impulse=-b.linear_velocity.dot(up);var request=-b.linear_velocity.dot(tangent)/k;var j=min(request,mu*normal_impulse)
            var expected=reference.solve(spheres,boxes,dt,0,mu=mu);var report=r.resolve(dt,coefficient=mu);compare_friction(r,expected);cone(r,report)
            var actual=decoded(r.normal.history.world.bodies.raw(),0);near(actual.linear_velocity.dot(tangent),b.linear_velocity.dot(tangent)+j);near(actual.angular_velocity.z,lever*j/.1)
            print("incline",hz,mu,"COM_t",actual.linear_velocity.dot(tangent),"omega_z",actual.angular_velocity.z,"normal_J",r.normal.impulses()[1],"tangent_J",report.maximum_tangent_impulse)
            var point_speed=actual.linear_velocity.dot(tangent)+lever*actual.angular_velocity.z
            if mu==.6:near(point_speed,Float64(0));assert_true(actual.linear_velocity.dot(tangent)<0)
            else:assert_true(point_speed<0);near(r.normal.impulses()[1],normal_impulse)
            r.close()
    print("G04b inclined no-slip rolling versus sliding support, analytic threshold/torque and timestep-scaled impulses passed")

def rotational_coupling() raises:
    for rotated in range(2):
        for reversed in range(2):
            for angle in [Float64(0),Float64(.6)]:
                var r=GpuFrictionResponse(basis_angle=angle);var reference=FrictionReference();var q=Quaternion.axis_angle(Vec3(1,2,3),.7) if rotated else Quaternion();var rotation=matrix(q)
                var a=sphere(apply(rotation,Vec3(1.4999,.5,.3)),2,v=apply(rotation,Vec3(-1,.7,.5)));a.orientation=q
                var b=RigidBody3D(MassProperties3D(3,Vec3(1,1.5,2)),orientation=q)
                var ss=List[OracleSphere]();var bs=List[OracleBox]()
                if reversed:bs.append(add_box(r.normal,b))
                ss.append(add_sphere(r.normal,a))
                if not reversed:bs.append(add_box(r.normal,b))
                var original: List[RigidBody3D]=[a,b];var before_p=momentum(original);var before_l=angular(original)
                var expected=reference.solve(ss,bs,1.0/60,0,vi=64,mu=.6);var report=r.resolve(1.0/60,coefficient=.6,velocity_iterations=64);compare_friction(r,expected);cone(r,report)
                var raw=r.normal.history.world.bodies.raw();var final: List[RigidBody3D]=[decoded(raw,Int(ss[0].body_handle.slot)),decoded(raw,Int(bs[0].body_handle.slot))]
                vector(momentum(final),before_p)
                # COM projection changes orbital L; compare the velocity-only
                # state at original COMs for the common-point impulse invariant.
                final[0].position=a.position;final[1].position=b.position;vector(angular(final),before_l)
                print("coupled",rotated,reversed,angle,"iterations",report.normal.velocity_iterations,"normal_J",r.normal.impulses()[1],"friction_residual",report.tangent_residual)
                assert_true(report.normal.velocity_iterations>1);assert_true(r.normal.impulses()[1]<1/(.5+1.0/3+.25/2+.09/1.5)-1e-4);r.close()
    print("G04b anisotropic rotational/coupled normal-tangent response, closed momentum and rigid-transform/slot/basis checks passed")

def shared_and_trajectories() raises:
    var r=GpuFrictionResponse();var reference=FrictionReference();var ss: List[OracleSphere]=[add_sphere(r.normal,sphere(Vec3(-.5,.5,0),v=Vec3(2,-1,.3))),add_sphere(r.normal,sphere(Vec3(.5,.5,0),v=Vec3(-1,-1,-.2)))];var bs: List[OracleBox]=[add_box(r.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))]
    var result=reference.solve(ss,bs,1.0/60,0,vi=64,mu=.4);var report=r.resolve(1.0/60,coefficient=.4,velocity_iterations=64);compare_friction(r,result);cone(r,report);assert_equal(report.normal.contacts,Int32(3));assert_true(report.normal.velocity_iterations>1);r.close()
    for hz in [30,60,120,240]:
        var moving=GpuFrictionResponse();var cr=FrictionReference();var spheres: List[OracleSphere]=[add_sphere(moving.normal,sphere(Vec3(0,.5,0),v=Vec3(2,0,0)))];var boxes: List[OracleBox]=[add_box(moving.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))];var dt=1.0/Float64(hz)
        for _ in range(hz):
            assert_equal(moving.normal.history.world.bodies.step(dt),0);_=spheres[0].body.integrate(dt)
            var expected=cr.solve(spheres,boxes,dt,0,mu=.6);var report=moving.resolve(dt,coefficient=.6);compare_friction(moving,expected);cone(moving,report)
            for i in range(len(expected.bodies)):
                if expected.slots[i]==0:spheres[0].body=expected.bodies[i]
        var actual=decoded(moving.normal.history.world.bodies.raw(),0);assert_true(actual.linear_velocity.x>1.4 and actual.linear_velocity.x<1.5);geometric(actual.position.y,.5-1e-5)
        var surface_slip=actual.linear_velocity.x+.5*actual.angular_velocity.z
        var predicted=actual.angular_velocity.z*(1e-5+.5*9.81*dt*dt)/2
        near(surface_slip,predicted)
        print("trajectory",hz,"vx",actual.linear_velocity.x,"omega_z",actual.angular_velocity.z,"post_projection_surface_slip",surface_slip,"frozen_point_prediction",predicted)
        moving.close()
    print("G04b shared-body contacts and one-second frictional trajectories at 30/60/120/240 Hz passed")

def maximum_contact_capacity() raises:
    var r=GpuFrictionResponse();var reference=FrictionReference();var ss=List[OracleSphere]()
    for i in range(63):
        var x=Float64(i%9)*1.1-4.4;var z=Float64(i//9)*1.1-3.3
        if i==0:x=-4
        elif i==1:x=-3.5
        ss.append(add_sphere(r.normal,sphere(Vec3(x,.25,z),radius=.25,v=Vec3(2,-1,0)),.25))
    var bs: List[OracleBox]=[add_box(r.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,4))]
    var expected=reference.solve(ss,bs,1.0/60,0,mu=.1);var report=r.resolve(1.0/60,coefficient=.1);compare_friction(r,expected);cone(r,report)
    assert_equal(report.normal.contacts,Int32(64));var jt=r.tangents();assert_equal(jt[0],Float64(0));assert_equal(jt[len(jt)-1],Float64(0))
    ss[2].body.position=Vec3(-3.75,.25,-3.0);_=r.normal.history.world.bodies.submit([BodyCommand.update(ss[2].body_handle,ss[2].body)])
    reject(r,50);r.close();print("G04b full 64-contact response capacity with guarded tangent storage and over-capacity rollback passed")

def invalid_and_rollback() raises:
    var r=GpuFrictionResponse();var s=add_sphere(r.normal,sphere(Vec3(0,.5,0),v=Vec3(2,-1,0)));var floor=add_box(r.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5));_=r.normal.history.update()
    _=r.normal.history.world.bodies.submit([BodyCommand.force(s.body_handle,Vec3(.1,.2,.3),Vec3(.01,.02,.03))]);var huge=Float64(1e308);var nan=huge*huge-huge*huge
    var invalid_reference=FrictionReference();var ss: List[OracleSphere]=[s];var bs: List[OracleBox]=[floor]
    for mu in [Float64(-.1),Float64(2.1),huge*huge,nan]:
        reject(r,62,mu)
        with assert_raises():_=invalid_reference.solve(ss,bs,1.0/60,0,mu=mu)
        assert_equal(invalid_reference.last_error,Int32(62))
    with assert_raises():_=invalid_reference.solve(ss,bs,0,0,mu=0)
    assert_equal(invalid_reference.last_error,Int32(51))
    for mode in range(2):
        var count=r.normal.history.world._detect_on_device();r.normal.history.world.bodies._ctx.enqueue_function[corrupt_contact](r.normal.history.world._contact_out,r.normal.history.world._contact_values,Int32(mode),grid_dim=1,block_dim=1);r.normal.history.world.bodies._ctx.synchronize()
        reject(r,Int32(53 if mode==0 else 54),prepared=True,count=Int32(count[1]))
    var count=r.normal.history.world._detect_on_device();s.body.position.x=.2;_=r.normal.history.world.bodies.submit([BodyCommand.update(s.body_handle,s.body)])
    reject(r,53,prepared=True,count=Int32(count[1]));r.close()
    var capacity=GpuFrictionResponse(0);_=add_sphere(capacity.normal,sphere(Vec3(0,0,0)));_=add_sphere(capacity.normal,sphere(Vec3(1,0,0)));reject(capacity,50);capacity.close()
    var overflow=GpuFrictionResponse()
    for _ in range(12):_=add_sphere(overflow.normal,sphere(Vec3(0,0,0),radius=.1),.1)
    reject(overflow,50);overflow.close()
    var coupled=GpuFrictionResponse();var a=sphere(Vec3(1.4999,.5,.3),2,v=Vec3(-1,.7,.5));_=add_sphere(coupled.normal,a);_=add_box(coupled.normal,RigidBody3D(MassProperties3D(3,Vec3(1,1.5,2))))
    reject(coupled,55,vi=1);coupled.close()
    var unsafe=GpuFrictionResponse();var cs=List[OracleSphere]();var none=List[OracleBox]();var energy_reference=FrictionReference()
    for i in range(3):cs.append(add_sphere(unsafe.normal,sphere(Vec3(Float64(i),0,0),v=Vec3(.5 if i==0 else 1.0 if i==1 else 0.0,0,0))))
    reject(unsafe,56,mu=.4,e=1)
    with assert_raises():_=energy_reference.solve(cs,none,1.0/60,1,mu=.4)
    assert_equal(energy_reference.last_error,Int32(56));unsafe.close()
    print("G04b invalid materials, stale/corrupt identities/poses, overflow and coupled nonconvergence preserve body/force/history bytes passed")

def main() raises:
    independent_block_laws();analytic_sliding();zero_equivalence();inclined_support();rotational_coupling();shared_and_trajectories();maximum_contact_capacity();invalid_and_rollback();rotated_boundary_regression()
    print("G04b actual GPU one-coefficient friction checkpoint qualified; cold serial solver, no separate static/dynamic coefficients")
