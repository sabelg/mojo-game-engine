"""Actual GPU math foundation for isolated multi-point box response."""
from std.collections import Array
from std.memory import Pointer
from std.testing import assert_equal,assert_true
from experimental.physics_gpu.lifecycle import GpuWorld
from experimental.physics_gpu.box_response_math import normal_block,reduce_patch
from experimental.physics_gpu.box_response_reference import reference_block
from experimental.physics_gpu.box_box_kernels import Patch
from mojo_game import Vec3

def math_kernel(output: Pointer[Float64,MutAnyOrigin]):
    var k: Array[Float64,16]=[2,.5,-1,.5,.5,2,.5,-1,-1,.5,2,.5,.5,-1,.5,2]
    var q=Array[Float64,4](fill=-1);var result=normal_block(k,q,4,1e-9)
    output[unsafe_offset=0]=1 if result.valid else 0
    for i in range(4):output[unsafe_offset=i+1]=result.impulse[i]
    var duplicate=Array[Float64,16](fill=.5);var repeated=normal_block(duplicate,q,2,1e-9)
    output[unsafe_offset=5]=1 if repeated.valid else 0
    for i in range(2):output[unsafe_offset=i+6]=repeated.impulse[i]
    var patch=Patch();patch.count=6
    patch.a[0]=Vec3(-1,0,-1);patch.a[1]=Vec3(-1,0,0);patch.a[2]=Vec3(-1,0,1);patch.a[3]=Vec3(1,0,-1);patch.a[4]=Vec3(1,0,1);patch.a[5]=Vec3(1,0,1)
    for i in range(6):patch.b[i]=patch.a[i]
    var reduced=reduce_patch(patch,Vec3(0,1,0),1e-14);output[unsafe_offset=8]=Float64(reduced.count)
    for i in range(reduced.count):output[unsafe_offset=9+i]=Float64(reduced.indices[i])

def math_foundation() raises:
    var world=GpuWorld();var output=world._ctx.enqueue_create_buffer[DType.float64](14);output.enqueue_fill(-987654321.25)
    world._ctx.enqueue_function[math_kernel](output,grid_dim=1,block_dim=1);world._ctx.synchronize()
    var k: Array[Float64,16]=[2,.5,-1,.5,.5,2,.5,-1,-1,.5,2,.5,.5,-1,.5,2];var q=Array[Float64,4](fill=-1);var expected=reference_block(k,q,4)
    with output.map_to_host() as values:
        assert_equal(values[0],Float64(1));assert_equal(values[5],Float64(1));assert_equal(values[8],Float64(4));assert_equal(values[13],Float64(-987654321.25))
        for i in range(4):assert_true(abs(Float64(values[i+1])-.5)<=1e-10);assert_true(abs(Float64(values[i+1])-expected[i])<=1e-10)
        assert_true(abs(Float64(values[6])-1)<=1e-10);assert_true(abs(Float64(values[7])-1)<=1e-10)
        for i in range(4):assert_equal(values[9+i],Float64(0 if i==0 else 2 if i==1 else 3 if i==2 else 4))
    world.close();print("Actual GPU PSD rank-three symmetric load, duplicate-constraint minimum norm, independent scalar null-space reference and footprint reduction passed")


from experimental.physics_gpu.box_response import GpuBoxResponse,BoxResponseReport
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.collision import BoxCommand
from mojo_game import RigidBody3D,MassProperties3D

def single_floor() raises:
    var response=GpuBoxResponse();var floor=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0));var body=RigidBody3D(MassProperties3D.box(2,Vec3(1,1,1)),position=Vec3(0,.49,0))
    body.linear_velocity=Vec3(0,-1,0)
    var handles=response.detection.world.bodies.submit([BodyCommand.create(floor),BodyCommand.create(body)]);_=response.detection.world.submit_boxes([BoxCommand.attach(handles[0],Vec3(5,.25,5)),BoxCommand.attach(handles[1],Vec3(.5,.5,.5))])
    var report=response.resolve(1.0/60);assert_equal(report.patches,Int32(1));assert_equal(report.points,Int32(4));assert_true(report.normal_residual<=2e-9);assert_true(report.maximum_depth<=1e-5+1e-9)
    var raw=response.detection.world.bodies.raw()
    for axis in range(3):assert_true(abs(raw[(11+axis)*258+2])<=1e-10);assert_true(abs(raw[(14+axis)*258+2])<=1e-10)
    assert_true(abs(raw[5*258+2]-(.5-1e-5))<=1e-10)
    with response._impulses.map_to_host() as impulses:
        for i in range(4):assert_true(abs(Float64(impulses[i+1])-.5)<=1e-10)
    response.close();print("Actual GPU box/floor four-point normal block: uniform pressure, zero torque, private projection and complete body commit passed")
def main() raises:
    dispatch()

from std.collections import List
from std.testing import assert_raises
from mojo_game import Quaternion
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.box_response_reference import CpuBoxResponse,CpuBoxResult
from experimental.physics_gpu.lifecycle import state_words,body_state
from experimental.physics_gpu.box_box import float_bits

def add_box_response(mut response: GpuBoxResponse,p: Vec3,half: Vec3=Vec3(.5,.5,.5),mass: Float64=2,v: Vec3=Vec3(0,0,0),omega: Vec3=Vec3(0,0,0),orientation: Quaternion=Quaternion()) raises -> OracleBox:
    var body=RigidBody3D(MassProperties3D.fixed() if mass==0 else MassProperties3D.box(mass,half*2),position=p,orientation=orientation);body.linear_velocity=v;body.angular_velocity=omega
    var handles=response.detection.world.bodies.submit([BodyCommand.create(body)]);var shapes=response.detection.world.submit_boxes([BoxCommand.attach(handles[0],half)])
    return OracleBox(shapes[0],handles[0],1,body,half,Vec3(0,0,0),Quaternion())

def near(a: Float64,b: Float64,tolerance: Float64=1e-10) raises:
    if abs(a-b)>tolerance*(1+abs(b)):print("BOX RESPONSE NEAR FAILED",a,b,tolerance)
    assert_true(abs(a-b)<=tolerance*(1+abs(b)))
def vector(a: Vec3,b: Vec3,tolerance: Float64=1e-10) raises:
    near(a.x,b.x,tolerance);near(a.y,b.y,tolerance);near(a.z,b.z,tolerance)
def states(mut response: GpuBoxResponse,models: List[OracleBox]) raises:
    var actual=response.detection.world.bodies.raw()
    for model in models:
        var words=state_words(body_state(model.body))
        for f in range(23):
            if abs(actual[f*258+Int(model.body_handle.slot)+1]-words[f])>1e-10*(1+abs(words[f])):print("STATE FIELD",model.body_handle.slot,f)
            near(actual[f*258+Int(model.body_handle.slot)+1],words[f])
def bits_equal(a: List[Float64],b: List[Float64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(float_bits(a[i]),float_bits(b[i]))

def cpu_floor_and_impacts() raises:
    for restitution in [Float64(0),Float64(.5),Float64(1)]:
        var response=GpuBoxResponse();var models: List[OracleBox]=[add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_response(response,Vec3(0,.49,0),v=Vec3(0,-2,0))]
        var cpu=CpuBoxResponse();var expected=cpu.solve(models,1.0/60,restitution);var report=response.resolve(1.0/60,restitution=restitution);states(response,expected.models);near(report.kinetic_before,expected.kinetic_before);near(report.kinetic_after,expected.kinetic_after)
        near(expected.models[1].body.linear_velocity.y,2*restitution);vector(expected.models[1].body.angular_velocity,Vec3(0,0,0))
        with response._impulses.map_to_host() as impulses:
            for i in range(4):near(Float64(impulses[i+1]),1+restitution)
        response.close()
    for offset in [Float64(-.3),Float64(.3)]:
        var response=GpuBoxResponse();var models: List[OracleBox]=[add_box_response(response,Vec3(0,-.25,0),Vec3(.5,.25,1),0),add_box_response(response,Vec3(offset,.49,0),v=Vec3(0,-1,0))]
        var cpu=CpuBoxResponse();var expected=cpu.solve(models,1.0/60);_=response.resolve(1.0/60);states(response,expected.models);vector(expected.models[1].body.angular_velocity,Vec3(0,0,0));response.close()
    for angle in [Float64(.12),Float64(-.12)]:
        var response=GpuBoxResponse();var q=Quaternion.axis_angle(Vec3(0,0,1),angle)
        var models: List[OracleBox]=[add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_response(response,Vec3(0,.54,0),v=Vec3(0,-1,0),orientation=q)]
        var cpu=CpuBoxResponse();var expected=cpu.solve(models,1.0/60);var report=response.resolve(1.0/60);states(response,expected.models);assert_true(report.points>=1 and report.points<=4);assert_true(abs(expected.models[1].body.angular_velocity.z)>.01);response.close()
    print("Actual GPU centered/offset support and face/edge impacts match independent CPU geometry, elimination/null-space response and analytic pressure/torque laws")

def closed_shared_and_friction() raises:
    for mu in [Float64(0),Float64(.2)]:
        var response=GpuBoxResponse();var models: List[OracleBox]=[add_box_response(response,Vec3(0,0,0),v=Vec3(1,.1,0)),add_box_response(response,Vec3(.99,0,0),v=Vec3(0,-.1,0))]
        var cpu=CpuBoxResponse();var expected=cpu.solve(models,1.0/60,0,mu,64,64);var report=response.resolve(1.0/60,coefficient=mu,velocity_iterations=64,position_iterations=64);states(response,expected.models)
        # Closed-system momentum at the projected poses before velocity impulses.
        var incoming=Vec3(0,0,0);var outgoing=Vec3(0,0,0);var initial_angular=Vec3(0,0,0);var final_angular=Vec3(0,0,0)
        for i in range(2):
            var original=models[i].body;var final=expected.models[i].body;incoming=incoming+original.linear_velocity*2;outgoing=outgoing+final.linear_velocity*2
            initial_angular=initial_angular+final.position.cross(original.linear_velocity*2)+original.angular_velocity*original.properties.inertia.x
            final_angular=final_angular+final.position.cross(final.linear_velocity*2)+final.angular_velocity*final.properties.inertia.x
        vector(incoming,outgoing);vector(initial_angular,final_angular);assert_true(report.kinetic_after<=report.kinetic_before+1e-9*(1+report.kinetic_before));response.close()
    for mu in [Float64(0),Float64(.2),Float64(.6)]:
        var response=GpuBoxResponse();var models: List[OracleBox]=[add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_response(response,Vec3(0,.49,0),v=Vec3(1,-.1,0))]
        var cpu=CpuBoxResponse();var expected=cpu.solve(models,1.0/60,0,mu,64,64);var report=response.resolve(1.0/60,coefficient=mu,velocity_iterations=64,position_iterations=64);states(response,expected.models)
        if mu==0:near(expected.models[1].body.linear_velocity.x,1);vector(expected.models[1].body.angular_velocity,Vec3(0,0,0))
        else:assert_true(expected.models[1].body.linear_velocity.x<1);assert_true(report.cone_excess<=1e-12)
        response.close()
    print("Actual GPU shared dynamic box constraints, projected-pose linear/angular balance, energy, frictionless motion and circular Coulomb friction match independent CPU spectral reference")

from std.sys import argv
from std.math import sqrt
from experimental.physics_gpu.response_reference import energy

def potential(models: List[OracleBox],g: Vec3) -> Float64:
    var result=Float64(0)
    for model in models:result-=model.body.properties.mass*model.body.position.dot(g)
    return result
def total_kinetic(models: List[OracleBox]) -> Float64:
    var result=Float64(0)
    for model in models:result+=energy(model.body)
    return result

def rest_trajectory(count: Int,hz: Int,mu: Float64=0,sliding: Bool=False,velocity_budget: Int32=64) raises:
    var response=GpuBoxResponse(velocity_budget=velocity_budget);var models=List[OracleBox]();models.append(add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0))
    for i in range(count):models.append(add_box_response(response,Vec3(0,.5+Float64(i)-1e-5*Float64(i+1),0),v=Vec3(Float64(1 if sliding else 0),0,0)))
    var start=models.copy();var g=Vec3(0,-9.81,0);var dt=Float64(1)/Float64(hz);var cpu=CpuBoxResponse(Int(velocity_budget));var maximum_drift=Float64(0);var jitter=Float64(0);var angle=Float64(0);var depth=Float64(0);var work=Float64(0);var dissipation=Float64(0);var iteration_used=0;var completed=0;var blocker=Int32(0);var initial_energy=total_kinetic(models)+potential(models,g);var energy_error=Float64(0)
    for frame in range(2*hz):
        var previous_energy=total_kinetic(models)+potential(models,g)
        assert_equal(response.detection.world.bodies.step(dt,g),Int32(0))
        for i in range(len(models)):_=models[i].body.integrate(dt,g)
        near(total_kinetic(models)+potential(models,g),previous_energy)
        var entry=models.copy();var raw_before=response.detection.world.bodies.raw();var cpu_failed=False
        var expected=CpuBoxResult(List[OracleBox](),List[Float64](),0,0,0,0,0,0,0,0)
        try:expected=cpu.solve(models,dt,0,mu,Int(velocity_budget),64)
        except:cpu_failed=True
        var gpu_failed=False;var report=BoxResponseReport(0,0,0,0,0,0,0,0,0,0,0,0)
        try:report=response.resolve(dt,coefficient=mu,velocity_iterations=velocity_budget,position_iterations=64)
        except:gpu_failed=True
        assert_equal(gpu_failed,cpu_failed)
        if gpu_failed:
            blocker=response.last_error;assert_equal(blocker,cpu.last_error);bits_equal(raw_before,response.detection.world.bodies.raw())
            with response._stats.map_to_host() as stats:
                print("BOX_REST_BLOCKER",count,hz,frame,blocker,"normal_residual",stats[2],"normal_gate",stats[5],"CPU_residual",cpu.last_normal_residual,"position_residual",cpu.last_position_residual)
            break
        states(response,expected.models);models=expected.models.copy();completed+=1
        work+=potential(models,g)-potential(entry,g);dissipation+=total_kinetic(entry)-total_kinetic(models)
        near((total_kinetic(models)+potential(models,g))-(total_kinetic(entry)+potential(entry,g)),(potential(models,g)-potential(entry,g))+(total_kinetic(models)-total_kinetic(entry)))
        energy_error=max(energy_error,(total_kinetic(models)+potential(models,g))-initial_energy-work+dissipation)
        depth=max(depth,report.maximum_depth);iteration_used=max(iteration_used,Int(report.velocity_sweeps))
        for i in range(1,len(models)):
            if not sliding:maximum_drift=max(maximum_drift,(models[i].body.position-start[i].body.position).length())
            if frame>=hz//2:jitter=max(jitter,max(models[i].body.linear_velocity.length(),models[i].body.angular_velocity.length()))
            var q=models[i].body.orientation;angle=max(angle,2*sqrt(q.x*q.x+q.y*q.y+q.z*q.z))
        assert_true(report.maximum_depth<=1e-5+1e-9);assert_true(energy_error<=1e-9*(1+abs(initial_energy)+work))
    if blocker==0 and not sliding:
        assert_true(maximum_drift<=1e-4);assert_true(jitter<=1e-3);assert_true(angle<=1e-3)
    if sliding and mu==0:
        near(models[1].body.position.x,Float64(2));near(models[1].body.linear_velocity.x,Float64(1));vector(models[1].body.angular_velocity,Vec3(0,0,0))
    print("BOX_MOTION_END",hz,mu,sliding,models[1].body.position.x,models[1].body.linear_velocity.x,models[1].body.angular_velocity.length())
    print("BOX_REST_RESULT",count,hz,"mu",mu,"sliding",sliding,"completed",completed,"blocker",blocker,"drift",maximum_drift,"jitter",jitter,"angle",angle,"depth",depth,"projection_work",work,"normal_dissipation",dissipation,"accounted_energy_gain",energy_error,"velocity_sweeps",iteration_used)
    response.close()

def dispatch() raises:
    var arguments=argv();var group=String("basic")
    if len(arguments)>1:group=arguments[1]
    if group=="convergence":convergence_diagnosis();return
    if group=="conditioning":conditioning();return
    if group=="basic":math_foundation();single_floor();cpu_floor_and_impacts();closed_shared_and_friction();contracts();return
    for count in [1,2,3]:
        for hz in [30,60,120,240]:
            if group=="rest-"+String(count)+"-"+String(hz):rest_trajectory(count,hz);return
    if group=="rest-3-30-96":rest_trajectory(3,30,velocity_budget=96);return
    for hz in [30,60,120,240]:
        if group=="slide-"+String(hz):rest_trajectory(1,hz,.2,True);return
        if group=="free-"+String(hz):rest_trajectory(1,hz,0,True);return
    raise Error("Unknown box response test group")


from experimental.physics_gpu.collision import SphereCommand
from experimental.physics_gpu.box_response_kernels import BR_CONFIG,BR_LIMIT,BR_PROFILE,BR_POSITION,BR_VELOCITY,BR_ENERGY,BR_TOPOLOGY
from experimental.physics_gpu.shape_kernels import SHAPE_STALE

def reject_response(mut response: GpuBoxResponse,code: Int32,dt: Float64=1.0/60,e: Float64=0,mu: Float64=0,vi: Int32=64,pi: Int32=64) raises:
    var before=response.detection.world.bodies.raw();var metadata=response.detection.world.bodies.metadata();var registry=response.detection.world.debug_registry()
    with assert_raises():_=response.resolve(dt,e,mu,vi,pi)
    assert_equal(response.last_error,code);bits_equal(before,response.detection.world.bodies.raw())
    var after_meta=response.detection.world.bodies.metadata();var after_registry=response.detection.world.debug_registry()
    for i in range(len(metadata)):assert_equal(metadata[i],after_meta[i])
    for i in range(len(registry[0])):assert_equal(registry[0][i],after_registry[0][i])
    bits_equal(registry[1],after_registry[1])

def contracts() raises:
    var response=GpuBoxResponse();var floor=add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0);var model=add_box_response(response,Vec3(0,.49,0),v=Vec3(0,-1,0))
    _=response.detection.world.bodies.submit([BodyCommand.force(model.body_handle,Vec3(.1,.2,.3),Vec3(.01,.02,.03))])
    var large=Float64(1e308);var nan=large*large-large*large
    for dt in [Float64(0),Float64(.1),Float64(1.0/1000),nan]:reject_response(response,BR_CONFIG,dt)
    for e in [Float64(-.1),Float64(1.1),nan]:reject_response(response,BR_CONFIG,e=e)
    for mu in [Float64(-.1),Float64(2.1),nan]:reject_response(response,BR_CONFIG,mu=mu)
    reject_response(response,BR_CONFIG,vi=0);reject_response(response,BR_CONFIG,vi=65);reject_response(response,BR_CONFIG,pi=0);reject_response(response,BR_CONFIG,pi=65)
    var entry=response.detection.world.bodies.raw();_=response.resolve(1.0/60);var after=response.detection.world.bodies.raw()
    for f in range(23):assert_equal(float_bits(entry[f*258+Int(floor.body_handle.slot)+1]),float_bits(after[f*258+Int(floor.body_handle.slot)+1]))
    for f in range(17,23):assert_equal(float_bits(entry[f*258+Int(model.body_handle.slot)+1]),float_bits(after[f*258+Int(model.body_handle.slot)+1]))
    var old_shape=model.shape;var old_body=model.body_handle;_=response.detection.world.bodies.submit([BodyCommand.remove(old_body)])
    model=add_box_response(response,Vec3(0,.49,0),v=Vec3(0,-1,0));assert_equal(model.shape.generation,old_shape.generation+1);assert_equal(model.body_handle.generation,old_body.generation+1)
    var saved=response.detection.world.bodies.raw()
    with assert_raises():_=response.detection.world.submit_boxes([BoxCommand.detach(old_shape)])
    assert_equal(response.detection.world.last_error,SHAPE_STALE);bits_equal(saved,response.detection.world.bodies.raw());_=response.resolve(1.0/60)
    response.close();response.close()
    with assert_raises():_=response.resolve(1.0/60)
    for cap in [Int32(0),Int32(3)]:
        var limited=GpuBoxResponse(cap);_=add_box_response(limited,Vec3(0,-.25,0),Vec3(5,.25,5),0);_=add_box_response(limited,Vec3(0,.49,0));reject_response(limited,BR_LIMIT);limited.close()
    for budget in [Int32(32),Int32(65),Int32(128)]:
        with assert_raises():_=GpuBoxResponse(velocity_budget=budget)
    for cap in [Int32(-1),Int32(65)]:
        with assert_raises():_=GpuBoxResponse(cap)
    var profile=GpuBoxResponse();_=add_box_response(profile,Vec3(0,0,0),mass=101);reject_response(profile,BR_PROFILE);profile.close()
    var mixed=GpuBoxResponse();_=add_box_response(mixed,Vec3(0,-.25,0),Vec3(5,.25,5),0);var handles=mixed.detection.world.bodies.submit([BodyCommand.create(RigidBody3D(MassProperties3D.sphere(2,.5),position=Vec3(0,3,0)))]);_=mixed.detection.world.submit_shapes([SphereCommand.attach(handles[0],.5)]);reject_response(mixed,BR_PROFILE);mixed.close()
    var deep=GpuBoxResponse();_=add_box_response(deep,Vec3(0,0,0));_=add_box_response(deep,Vec3(.6,0,0));reject_response(deep,BR_POSITION);deep.close()
    var topology=GpuBoxResponse();_=add_box_response(topology,Vec3(0,0,0));_=add_box_response(topology,Vec3(.9,0,0));_=add_box_response(topology,Vec3(1.91,0,0));reject_response(topology,BR_TOPOLOGY);topology.close()
    var energetic=GpuBoxResponse()
    for i in range(3):_=add_box_response(energetic,Vec3(Float64(i),0,0),v=Vec3(.5 if i==0 else 1.0 if i==1 else 0.0,0,0))
    reject_response(energetic,BR_ENERGY,e=1);energetic.close()
    for velocity_failure in [False,True]:
        var chain=GpuBoxResponse();_=add_box_response(chain,Vec3(0,-.25,0),Vec3(5,.25,5),0);_=add_box_response(chain,Vec3(0,.5-1e-5,0));_=add_box_response(chain,Vec3(0,1.5-2e-5,0));assert_equal(chain.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0))
        reject_response(chain,BR_VELOCITY if velocity_failure else BR_POSITION,dt=1.0/30,vi=Int32(1 if velocity_failure else 64),pi=Int32(64 if velocity_failure else 1));_=chain.resolve(1.0/30,velocity_iterations=64,position_iterations=64);chain.close()
    for full in [False,True]:
        var capacity=GpuBoxResponse();_=add_box_response(capacity,Vec3(0,-.25,0),Vec3(10,.25,5),0)
        for i in range(16 if full else 17):_=add_box_response(capacity,Vec3(-8.5+Float64(i),.39,0),Vec3(.4,.4,.4),v=Vec3(0,-1,0))
        if full:
            var report=capacity.resolve(1.0/60);assert_equal(report.patches,Int32(16));assert_equal(report.points,Int32(64))
        else:reject_response(capacity,BR_LIMIT)
        capacity.close()
    var empty=GpuBoxResponse(0);var report=empty.resolve(1.0/60);assert_equal(report.points,Int32(0));empty.close()
    print("Actual GPU box response config/profile/depth/topology/energy/capacity/iteration/stale/closed rejection, retry, 16 patches/64 points, fixed/force/torque and full authoritative byte rollback passed")

def convergence_case(hz: Int,mass_scale: Float64,load: Float64,budget: Int32,iterations: Int32) raises:
    var response=GpuBoxResponse(velocity_budget=budget);var models=List[OracleBox]();models.append(add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0))
    for i in range(3):models.append(add_box_response(response,Vec3(0,.5+Float64(i)-1e-5*Float64(i+1),0),mass=2*mass_scale))
    var dt=Float64(1)/Float64(hz);var g=Vec3(0,-9.81*load,0);assert_equal(response.detection.world.bodies.step(dt,g),Int32(0))
    for i in range(len(models)):_=models[i].body.integrate(dt,g)
    var before=response.detection.world.bodies.raw();var cpu=CpuBoxResponse(Int(budget));var cpu_failed=False;var gpu_failed=False
    var expected=CpuBoxResult(List[OracleBox](),List[Float64](),0,0,0,0,0,0,0,0)
    try:expected=cpu.solve(models,dt,0,0,Int(iterations),64)
    except:cpu_failed=True
    try:_=response.resolve(dt,velocity_iterations=iterations,position_iterations=64)
    except:gpu_failed=True
    assert_equal(gpu_failed,cpu_failed)
    var history=response.residual_history();assert_equal(len(history),len(cpu.normal_history));var predicted=9.81*load*dt*.5
    for i in range(len(history)):
        near(history[i],predicted);near(history[i],cpu.normal_history[i]);print("BOX_RESIDUAL",hz,mass_scale,load,budget,iterations,i+1,history[i],predicted);predicted*=.75
    var gate=1e-9*(1+9.81*load*dt)
    if gpu_failed:assert_equal(response.last_error,Int32(114));bits_equal(before,response.detection.world.bodies.raw())
    else:
        states(response,expected.models)
        # Direct independent equilibrium of the 3x3 translational Delassus system.
        # Exact total impulses are (3m*gdt, 2m*gdt, m*gdt); velocity residual
        # explains the finite-iteration force error, not an altered contact law.
        with response._impulses.map_to_host() as impulses:
            for patch in range(3):
                var total=Float64(0)
                for i in range(4):total+=Float64(impulses[1+patch*4+i])
                assert_true(abs(total-Float64(3-patch)*2*mass_scale*9.81*load*dt)<=32*mass_scale*gate)
    print("BOX_CONVERGENCE_RESULT",hz,mass_scale,load,budget,iterations,"used",len(history),"failure",response.last_error,"gate",gate)
    response.close()

def convergence_diagnosis() raises:
    for iterations in [Int32(16),Int32(32),Int32(64)]:convergence_case(30,1,1,64,iterations)
    convergence_case(30,1,1,96,96)
    for hz in [60,120,240]:convergence_case(hz,1,1,64,64)
    for mass_scale in [Float64(.25),Float64(4)]:convergence_case(30,mass_scale,1,64,64);convergence_case(30,mass_scale,1,96,96)
    for load in [Float64(.5),Float64(2)]:convergence_case(30,1,load,64,64);convergence_case(30,1,load,96,96)
    print("GPU residual histories match independent scalar three-body system with contraction .75; original64 counterexample retained and explicit96 policy compared")

def conditioning() raises:
    var state=UInt64(0xc0d20261013);var passed=0;var rejected=0
    for scale in [Float64(1e-12),Float64(1e-10),Float64(1e-8),Float64(1e-6)]:
        for sample in range(8):
            state=state^(state<<7);state=state^(state>>9);state=state^(state<<8);var j=Float64(state&65535)/65535*2-1
            state=state^(state<<7);state=state^(state>>9);state=state^(state<<8);var k=Float64(state&65535)/65535*2-1
            var q=Quaternion.axis_angle(Vec3(0,0,1),.57);var perturbed=q*Quaternion.axis_angle(Vec3(.3,-.7,.2),scale*j)
            var response=GpuBoxResponse();var models: List[OracleBox]=[add_box_response(response,Vec3(0,0,0),Vec3(.9,.65,.23),0,orientation=q),add_box_response(response,Vec3(scale*j,scale*k,.46-2e-8),Vec3(.9,.65,.23),v=Vec3(0,0,-.1),orientation=perturbed)]
            var before=response.detection.world.bodies.raw();var cpu=CpuBoxResponse();var cpu_failed=False;var gpu_failed=False;var expected=CpuBoxResult(List[OracleBox](),List[Float64](),0,0,0,0,0,0,0,0)
            try:_=response.resolve(1.0/60,velocity_iterations=64,position_iterations=64)
            except:gpu_failed=True
            # Declare the SAT feature convention only. CPU independently checks
            # that any differing face is an equivalent representation-scale tie,
            # then reconstructs all normals/corners/points and solves from input.
            with response.detection._features.map_to_host() as features:cpu.conventions.append(Int32(features[1]))
            try:expected=cpu.solve(models,1.0/60,0,0,64,64)
            except:cpu_failed=True
            assert_equal(cpu_failed,gpu_failed)
            if gpu_failed:
                assert_equal(response.last_error,cpu.last_error);bits_equal(before,response.detection.world.bodies.raw());rejected+=1
                print("BOX_CONDITION_REJECTION",scale,sample,response.last_error)
            else:states(response,expected.models);passed+=1
            response.close()
    print("BOX_CONDITION_RESULT",passed,rejected,"seeded near-parallel reduced-patch independent pressure/state or explicit rollback outcomes")
