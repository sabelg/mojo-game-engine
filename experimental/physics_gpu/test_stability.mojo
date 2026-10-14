"""Separate original counterexample and corrected-order stability qualification."""
from std.collections import List
from std.memory import Pointer
from experimental.physics_gpu.shape_kernels import sphere_box
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.stable_friction import GpuStableFrictionResponse
from experimental.physics_gpu.stable_reference import StableReference
from experimental.physics_gpu.friction_response import GpuFrictionResponse,FrictionReport
from experimental.physics_gpu.normal_response import ResponseReport
from experimental.physics_gpu.friction_reference import FrictionReference
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import OracleBox,mixed_frame,matrix,apply,oracle_box_contact
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.test_g04a import add_sphere,add_box,sphere,fixed,decoded,near,geometric,vector,momentum,angular,rotated_boundary_regression,corrupt_contact
from experimental.physics_gpu.test_g04b import compare_friction,cone

def trajectory(hz: Int,corrected: Bool,mu: Float64,seconds: Int=1,radius: Float64=.35,vx: Float64=3,omega: Float64=4,start: Float64=-2,half: Float64=5) raises:
    var legacy=GpuFrictionResponse();var stable=GpuStableFrictionResponse();var b=sphere(Vec3(start,radius,-1.2 if mu==.02 else 1.2),radius=radius,v=Vec3(vx,0,0));b.angular_velocity=Vec3(0,0,omega)
    var old_s=add_sphere(legacy.normal,b,radius);var old_b=add_box(legacy.normal,fixed(Vec3(0,-.15,0)),Vec3(half,.15,4))
    var new_s=add_sphere(stable.response.normal,b,radius);var new_b=add_box(stable.response.normal,fixed(Vec3(0,-.15,0)),Vec3(half,.15,4))
    var spheres: List[OracleSphere]=[new_s if corrected else old_s];var boxes: List[OracleBox]=[new_b if corrected else old_b]
    var old_reference=FrictionReference();var new_reference=StableReference();var dt=1.0/Float64(hz);var actual=b
    var initial_energy=b.kinetic_energy()+9.81*b.position.y;var maximum_energy=initial_energy;var rest_energy=Float64(0);var drift=Float64(0);var final_report=FrictionReport(ResponseReport(0,0,0,0,0,0,0,0,0),mu,0,0,0,0)
    for frame in range(hz*seconds):
        _=spheres[0].body.integrate(dt)
        if corrected:
            assert_equal(stable.response.normal.history.world.bodies.step(dt),0)
            var pre=decoded(stable.response.normal.history.world.bodies.raw(),0)
            var expected=new_reference.solve(spheres,boxes,dt,0,mu=mu);var report=stable.resolve(dt,coefficient=mu)
            compare_friction(stable.response,expected.result);cone(stable.response,report.friction);final_report=report.friction
            spheres[0].body=expected.result.bodies[0];actual=decoded(stable.response.normal.history.world.bodies.raw(),0)
            # Explicit potential work of COM correction and normal kinetic loss.
            var delta_total=actual.kinetic_energy()-pre.kinetic_energy()+9.81*(actual.position.y-pre.position.y)
            var tangent_before=.5*(pre.linear_velocity.x*pre.linear_velocity.x+pre.properties.inertia.z*pre.angular_velocity.z*pre.angular_velocity.z)
            var tangent_after=.5*(actual.linear_velocity.x*actual.linear_velocity.x+actual.properties.inertia.z*actual.angular_velocity.z*actual.angular_velocity.z)
            near(delta_total,tangent_after-tangent_before-.5*pre.linear_velocity.y*pre.linear_velocity.y+9.81*(actual.position.y-pre.position.y))
        else:
            assert_equal(legacy.normal.history.world.bodies.step(dt),0)
            var expected=old_reference.solve(spheres,boxes,dt,0,mu=mu);var report=legacy.resolve(dt,coefficient=mu)
            compare_friction(legacy,expected);cone(legacy,report);final_report=report;spheres[0].body=expected.bodies[0];actual=decoded(legacy.normal.history.world.bodies.raw(),0)
        var total=actual.kinetic_energy()+9.81*actual.position.y;maximum_energy=max(maximum_energy,total)
        assert_true(total<=initial_energy+1e-8)
        if frame==hz:rest_energy=total
        if frame>hz:drift=max(drift,abs(total-rest_energy))
    var inertia=b.properties.inertia.z;var lever=radius-1e-5/2 if corrected else radius-(1e-5+.5*9.81*dt*dt)/2
    # Original first frame starts at zero overlap; resting slop appears only
    # after its velocity solve. Account for that first torque separately.
    var first_lever=lever if corrected else lever+1e-5/2
    var first_j=min((vx+first_lever*omega)/(1+first_lever*first_lever/inertia),mu*9.81*dt)
    var extra_torque=first_j*(first_lever-lever)
    var request=(vx+lever*omega-lever*extra_torque/inertia)/(1+lever*lever/inertia);var j=min(request,mu*9.81*Float64(seconds))
    near(actual.linear_velocity.x,vx-j);near(actual.angular_velocity.z,omega-(lever*j+extra_torque)/inertia)
    var surface_slip=actual.linear_velocity.x+radius*actual.angular_velocity.z
    var midpoint_slip=actual.linear_velocity.x+lever*actual.angular_velocity.z
    if mu==.8 or (seconds>1 and mu==.6):
        near(midpoint_slip,Float64(0));near(surface_slip,actual.angular_velocity.z*(radius-lever))
        if corrected:assert_true(abs(surface_slip)<.001)
        elif hz==60:assert_true(abs(surface_slip)>.001)
        elif hz==240:assert_true(abs(surface_slip)<.001)
    if mu==.02:
        var t=Float64(seconds);var discrete=start+vx*t-.5*mu*9.81*t*(t-dt)
        near(actual.position.x,discrete);near(midpoint_slip,vx+lever*omega-lever*extra_torque/inertia-(1+lever*lever/inertia)*j)
        assert_true(surface_slip>3)
    if seconds>1:assert_true(drift<1e-8)
    print("measurement",hz,Int(corrected),mu,seconds,"vx",actual.linear_velocity.x,"omega",actual.angular_velocity.z,"surface",surface_slip,"midpoint",midpoint_slip,"x",actual.position.x,"energy",actual.kinetic_energy(),"drift",drift,"max_total",maximum_energy)
    legacy.close();stable.close()

def counterexample_and_refinement() raises:
    for hz in [60,240]:
        for mu in [Float64(.02),Float64(.8)]:trajectory(hz,False,mu)
    for hz in [30,60,120,240]:
        for mu in [Float64(.02),Float64(.8)]:trajectory(hz,True,mu)
    trajectory(60,True,.6,5,.5,2,0,-5,10)
    print("Stability original 60Hz failure, original 240Hz pass, corrected original-scene 60Hz gate, four-timestep laws and five-second energy stability passed")

def inclination_and_transition(hz: Int) raises:
    var q=Quaternion.axis_angle(Vec3(0,0,1),.1);var rotation=matrix(q);var up=apply(rotation,Vec3(0,1,0));var tangent=apply(rotation,Vec3(1,0,0))
    var r=GpuStableFrictionResponse();var reference=StableReference();var initial=sphere(up*.5)
    var floor=RigidBody3D(MassProperties3D.fixed(),position=up*(-.1),orientation=q)
    var ss: List[OracleSphere]=[add_sphere(r.response.normal,initial)];var bs: List[OracleBox]=[add_box(r.response.normal,floor,Vec3(10,.1,4))]
    var first_slip=Float64(0);var last_slip=Float64(0);var slides=Int(0);var initial_total=9.81*initial.position.y;var high_loss=Float64(0);var expected_high=Float64(0);var accumulated_loss=Float64(0);var expected_loss=Float64(0);var lever=.5-1e-5/2;var k=1+lever*lever/.1
    for frame in range(hz*3):
        var mu=Float64(.6 if frame<hz else .005);var dt=1.0/Float64(hz)
        var before=ss[0].body;var before_total=before.kinetic_energy()+9.81*before.position.y
        var incoming_tangent=before.linear_velocity.dot(tangent)+lever*before.angular_velocity.z-9.81*up.x*(-1)*dt
        var j=min(max(0.0,-incoming_tangent/k),mu*9.81*up.y*dt)
        var energy_prediction=incoming_tangent*j+.5*k*j*j-(9.81*up.y*1e-5 if frame==0 else 0.0)
        assert_equal(r.response.normal.history.world.bodies.step(dt),0);_=ss[0].body.integrate(dt)
        var expected=reference.solve(ss,bs,dt,0,mu=mu);var report=r.resolve(dt,coefficient=mu);compare_friction(r.response,expected.result);cone(r.response,report.friction)
        ss[0].body=expected.result.bodies[0];var actual=decoded(r.response.normal.history.world.bodies.raw(),0)
        var slip=actual.linear_velocity.dot(tangent)+.5*actual.angular_velocity.z
        if frame==hz-1:first_slip=slip;assert_true(abs(slip)<.001);assert_true(actual.linear_velocity.dot(tangent)<0)
        if frame>=hz and report.friction.sliding_contacts>0:slides+=1
        if frame==hz*3-1:last_slip=slip;assert_true(slip<-.5)
        var total=actual.kinetic_energy()+9.81*actual.position.y
        assert_true(total<=initial_total+1e-8)
        near(total-before_total,energy_prediction);expected_loss-=energy_prediction;accumulated_loss=initial_total-total
        if frame==hz-1:high_loss=accumulated_loss;expected_high=expected_loss
    print("incline_transition",hz,first_slip,last_slip,slides,"high_energy_loss",high_loss,"analytic_high_loss",expected_high,"total_loss",accumulated_loss,"analytic_total_loss",expected_loss);assert_true(slides>hz);r.close()
    print("Stability inclined rolling support and coefficient-driven physical sliding transition passed")

def geometry_probe(bounds: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    var c=sphere_box(bounds,0,1);output[unsafe_offset=0]=c.normal.x;output[unsafe_offset=1]=c.normal.y;output[unsafe_offset=2]=c.normal.z;output[unsafe_offset=3]=c.separation

def coupled_rotating_and_bookkeeping() raises:
    for angle in [Float64(0),Float64(.6)]:
        var r=GpuStableFrictionResponse(basis_angle=angle);var reference=StableReference()
        var a=sphere(Vec3(1.4999,.5,.3),2,v=Vec3(-1,.7,.5));var box=RigidBody3D(MassProperties3D(3,Vec3(1,1.5,2)));box.angular_velocity=Vec3(0,0,.2)
        var ss: List[OracleSphere]=[add_sphere(r.response.normal,a)];var bs: List[OracleBox]=[add_box(r.response.normal,box)]
        var original: List[RigidBody3D]=[a,box];var old_p=momentum(original);var old_l=angular(original)
        var expected=reference.solve(ss,bs,1.0/60,0,vi=64,mu=.6);var report=r.resolve(1.0/60,coefficient=.6,velocity_iterations=64);compare_friction(r.response,expected.result);cone(r.response,report.friction)
        var raw=r.response.normal.history.world.bodies.raw();var final: List[RigidBody3D]=[decoded(raw,0),decoded(raw,1)];vector(momentum(final),old_p)
        # Projection orbital change uses incoming momenta, then common-point
        # velocity impulses conserve angular momentum at projected COMs.
        var delta=(final[0].position-a.position).cross(a.linear_momentum())+(final[1].position-box.position).cross(box.linear_momentum())
        vector(angular(final),old_l+delta)
        ss[0].body=final[0];bs[0].body=final[1];var normal_before=oracle_box_contact(ss[0],bs[0]).normal;var change=Float64(0);var released=Int(0);var probe=r.response.normal.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](4)
        for _ in range(8):
            assert_equal(r.response.normal.history.world.bodies.step(1.0/240,Vec3(0,0,0)),0);_=ss[0].body.integrate(1.0/240,Vec3(0,0,0));_=bs[0].body.integrate(1.0/240,Vec3(0,0,0))
            var current=reference.solve(ss,bs,1.0/240,0,vi=64,mu=.6);var update=r.resolve(1.0/240,coefficient=.6,velocity_iterations=64);compare_friction(r.response,current.result);cone(r.response,update.friction)
            ss[0].body=current.result.bodies[0];bs[0].body=current.result.bodies[1];var frame=mixed_frame(ss,bs)
            var observed=r.response.normal.history.world.detect();assert_equal(len(observed.contacts),len(frame.contacts))
            var expected_geometry=oracle_box_contact(ss[0],bs[0])
            r.response.normal.history.world.bodies._ctx.enqueue_function[geometry_probe](r.response.normal.history.world._bounds,probe,grid_dim=1,block_dim=1);r.response.normal.history.world.bodies._ctx.synchronize()
            with probe.map_to_host() as values:
                vector(Vec3(Float64(values[0]),Float64(values[1]),Float64(values[2])),expected_geometry.normal);geometric(Float64(values[3]),expected_geometry.separation)
            change=max(change,(expected_geometry.normal-normal_before).length())
            if len(frame.contacts)==0:released+=1;assert_true(expected_geometry.separation>0)
        assert_true(change>1e-4);print("rotating_geometry",angle,change,"released",released);r.close()
    var r=GpuStableFrictionResponse();var reference=StableReference();var ss: List[OracleSphere]=[add_sphere(r.response.normal,sphere(Vec3(-.5,.49,0),v=Vec3(2,-1,.3))),add_sphere(r.response.normal,sphere(Vec3(.5,.49,0),v=Vec3(-1,-1,-.2)))];var bs: List[OracleBox]=[add_box(r.response.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))]
    var expected=reference.solve(ss,bs,1.0/60,0,vi=64,mu=.4);var report=r.resolve(1.0/60,coefficient=.4,velocity_iterations=64);compare_friction(r.response,expected.result);cone(r.response,report.friction);assert_equal(report.initial_contacts,Int32(3));r.close()
    print("Stability projected-COM angular bookkeeping, fresh rotating geometry and shared contacts passed")

def reject(mut r: GpuStableFrictionResponse,code: Int32,mu: Float64=.4,vi: Int32=32,pi: Int32=32,e: Float64=0,prepared: Bool=False,count: Int32=0) raises:
    var before=r.response.normal.history.world.bodies.raw();var cache=r.response.normal.history.debug_cache();var meta=r.response.normal.history.world.bodies.metadata();var returned=False
    with assert_raises():
        if prepared:_=r._solve_prepared(count,1.0/60,e,vi,pi,mu)
        else:_=r.resolve(1.0/60,e,mu,vi,pi)
        returned=True
    assert_true(not returned);assert_equal(r.response.normal.last_error,code)
    var after=r.response.normal.history.world.bodies.raw();var after_cache=r.response.normal.history.debug_cache();var after_meta=r.response.normal.history.world.bodies.metadata()
    for i in range(len(before)):assert_equal(before[i],after[i])
    for i in range(len(meta)):assert_equal(meta[i],after_meta[i])
    for i in range(len(cache[0])):assert_equal(cache[0][i],after_cache[0][i])
    for i in range(len(cache[1])):assert_equal(cache[1][i],after_cache[1][i])
    for i in range(5):assert_equal(cache[2][i],after_cache[2][i])

def edge_cases_and_transactions() raises:
    for speed in [Float64(0),Float64(1e-12),Float64(1e-8)]:
        var r=GpuStableFrictionResponse();_=add_sphere(r.response.normal,sphere(Vec3(0,.48,0),v=Vec3(speed,-1,0)));_=add_box(r.response.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))
        var report=r.resolve(1.0/60,coefficient=.8);cone(r.response,report.friction);var body=decoded(r.response.normal.history.world.bodies.raw(),0);var lever=.5-1e-5/2;var j=speed/(1+lever*lever/.1)
        near(body.linear_velocity.x,speed-j);near(body.angular_velocity.z,-lever*j/.1);r.close()
    for restitution in [Float64(0),Float64(.5),Float64(1)]:
        var bounce=GpuStableFrictionResponse();var br=StableReference();var sp: List[OracleSphere]=[add_sphere(bounce.response.normal,sphere(Vec3(0,.48,0),v=Vec3(2,-1,0)))];var bx: List[OracleBox]=[add_box(bounce.response.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))]
        var predicted=br.solve(sp,bx,1.0/60,restitution,mu=.1);var report=bounce.resolve(1.0/60,restitution,.1);compare_friction(bounce.response,predicted.result);cone(bounce.response,report.friction)
        var actual=decoded(bounce.response.normal.history.world.bodies.raw(),0);var lever=.5-1e-5/2;var j=.1*(1+restitution)
        near(actual.linear_velocity.y,restitution);near(actual.linear_velocity.x,2-j);near(actual.angular_velocity.z,-lever*j/.1)
        near(report.friction.normal.energy_after,.5*((2-j)**2+restitution*restitution)+.05*(lever*j/.1)**2);bounce.close()
    var r=GpuStableFrictionResponse();var ss: List[OracleSphere]=[add_sphere(r.response.normal,sphere(Vec3(0,.48,0),v=Vec3(2,-1,0)))];var bs: List[OracleBox]=[add_box(r.response.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))];_=r.response.normal.history.update()
    _=r.response.normal.history.world.bodies.submit([BodyCommand.force(ss[0].body_handle,Vec3(.1,.2,.3),Vec3(.01,.02,.03))]);reject(r,62,mu=-.1)
    var count=r.response.normal.history.world._detect_on_device();r.response.normal.history.world.bodies._ctx.enqueue_function[corrupt_contact](r.response.normal.history.world._contact_out,r.response.normal.history.world._contact_values,Int32(0),grid_dim=1,block_dim=1);r.response.normal.history.world.bodies._ctx.synchronize();reject(r,53,prepared=True,count=Int32(count[1]));r.close()
    var topology=GpuStableFrictionResponse();_=add_sphere(topology.response.normal,sphere(Vec3(0,0,0)));_=add_sphere(topology.response.normal,sphere(Vec3(.9,0,0)));_=add_sphere(topology.response.normal,sphere(Vec3(1.91,0,0)));reject(topology,65);topology.close()
    var position=GpuStableFrictionResponse()
    for i in range(3):_=add_sphere(position.response.normal,sphere(Vec3(Float64(i)*.9,0,0)))
    reject(position,58,pi=1);position.close()
    var capacity=GpuStableFrictionResponse(0);_=add_sphere(capacity.response.normal,sphere(Vec3(0,0,0)));_=add_sphere(capacity.response.normal,sphere(Vec3(1,0,0)));reject(capacity,50);capacity.close()
    var energy=GpuStableFrictionResponse()
    for i in range(3):_=add_sphere(energy.response.normal,sphere(Vec3(Float64(i),0,0),v=Vec3(.5 if i==0 else 1.0 if i==1 else 0.0,0,0)))
    reject(energy,56,e=1);energy.close()
    var release=GpuStableFrictionResponse();var reference=StableReference();var rs: List[OracleSphere]=[add_sphere(release.response.normal,sphere(Vec3(0,0,0))),add_sphere(release.response.normal,sphere(Vec3(1,0,0)))];var rb: List[OracleBox]=[add_box(release.response.normal,fixed(Vec3(.5,0,0)),Vec3(.1,1,1))]
    var expected=reference.solve(rs,rb,1.0/60,0,mu=.4);var report=release.resolve(1.0/60,coefficient=.4);compare_friction(release.response,expected.result);assert_equal(report.initial_contacts,Int32(3));assert_equal(report.projected_contacts,Int32(2));release.close()
    print("Stability near-zero, material/identity/topology/iteration/capacity/energy rollback and legitimate contact release passed")

def corrected_capacity_and_zero() raises:
    var r=GpuStableFrictionResponse();var reference=StableReference();var ss=List[OracleSphere]()
    for i in range(63):
        var x=Float64(i%9)*1.1-4.4;var z=Float64(i//9)*1.1-3.3
        if i==0:x=-4
        elif i==1:x=-3.5
        ss.append(add_sphere(r.response.normal,sphere(Vec3(x,.25,z),radius=.25,v=Vec3(2,-1,0)),.25))
    var bs: List[OracleBox]=[add_box(r.response.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,4))]
    var expected=reference.solve(ss,bs,1.0/60,0,mu=.1);var report=r.resolve(1.0/60,coefficient=.1);compare_friction(r.response,expected.result);cone(r.response,report.friction);assert_equal(report.projected_contacts,Int32(64));r.close()
    var zero=GpuStableFrictionResponse();var zr=StableReference();var zs: List[OracleSphere]=[add_sphere(zero.response.normal,sphere(Vec3(0,.48,0),v=Vec3(2,-1,0)))];var zb: List[OracleBox]=[add_box(zero.response.normal,fixed(Vec3(0,-.1,0)),Vec3(5,.1,5))]
    var result=zr.solve(zs,zb,1.0/60,0,mu=0);var nofriction=zero.resolve(1.0/60,coefficient=0);compare_friction(zero.response,result.result);near(decoded(zero.response.normal.history.world.bodies.raw(),0).linear_velocity.x,Float64(2));cone(zero.response,nofriction.friction);zero.close()
    print("Stability corrected full 64-contact capacity and zero-coefficient fresh normal solve passed")

def main() raises:
    counterexample_and_refinement();inclination_and_transition(60);inclination_and_transition(120);coupled_rotating_and_bookkeeping();edge_cases_and_transactions();corrected_capacity_and_zero();rotated_boundary_regression()
    print("Bounded position-first stability checkpoint qualified; original baselines unchanged, exact material surface sticking still limited by slop")
