"""Bounded independently replayed interacting box trajectories; failures are evidence."""
from std.collections import List
from std.testing import assert_true,assert_equal,assert_raises
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.box_response import GpuBoxResponse,BoxResponseReport
from experimental.physics_gpu.box_response_reference import CpuBoxResponse,CpuBoxResult,cpu_geometry
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.test_box_response import add_box_response,near,vector,bits_equal,total_kinetic,potential
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.box_box import float_bits

def noise(seed: Int,k: Int) -> Float64:return Float64((seed*(17*k+13)+29*k)%97)/48-1

def transform_body(b: RigidBody3D,variant: Int) -> RigidBody3D:
    var result=b
    if variant==1:result.position=result.position+Vec3(2,0,1)
    if variant==2:
        result.position.x=-result.position.x;result.linear_velocity.x=-result.linear_velocity.x
        result.angular_velocity.y=-result.angular_velocity.y;result.angular_velocity.z=-result.angular_velocity.z
        result.orientation.y=-result.orientation.y;result.orientation.z=-result.orientation.z
    return result

def inputs(mut gpu: GpuBoxResponse,id: Int,seed: Int,variant: Int) raises -> List[OracleBox]:
    var models=List[OracleBox]()
    if id!=8:
        var floor=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0));floor=transform_body(floor,variant)
        models.append(add_box_response(gpu,floor.position,Vec3(.5,.25,1) if id==9 else Vec3(5,.25,5),0,orientation=floor.orientation))
    var count=3 if id==10 else 2 if id==0 or id==1 or id==3 or id==5 or id==8 else 1
    for i in range(count):
        var p=Vec3(0,.5+Float64(i)-Float64(i+1)*1e-5,0);var q=Quaternion();var v=Vec3(0,0,0);var w=Vec3(0,0,0)
        if id==0 and i==1:p.x=.06
        if id==1:q=Quaternion.axis_angle(Vec3(0,1,0),.02 if i==0 else -.02);p.x=.03 if i==1 else 0
        if id==2:
            q=Quaternion.axis_angle(Vec3(0,0,1),.02)
            p.y=.5*(abs(q.rotate(Vec3(1,0,0)).y)+abs(q.rotate(Vec3(0,1,0)).y)+abs(q.rotate(Vec3(0,0,1)).y))-1e-5
        if id==3:v=Vec3(.3,0,.05);p.x=.03 if i==1 else 0
        if id==4:q=Quaternion.axis_angle(Vec3(0,1,0),.02);v=Vec3(.3,0,.1);w=Vec3(0,.1,0)
        if id==5:
            q=Quaternion.axis_angle(Vec3(0,1,0),.01+.002*noise(seed,i+2));v=Vec3(1e-4*noise(seed,i+4),0,1e-4*noise(seed,i+6));w=Vec3(0,1e-4*noise(seed,i+8),0)
            if i==1:p.x=.02+.001*noise(seed,0);p.z=.001*noise(seed,1)
        if id==6:p.y=.7
        if id==8:p=Vec3(-.55 if i==0 else .55,0,0);v=Vec3(.5 if i==0 else -.5,.04 if i==0 else -.04,0)
        if id==9:p.x=.3;v=Vec3(.5,0,0)
        if id==10:p.x=0 if i==0 else .03 if i==1 else -.03
        var body=RigidBody3D(MassProperties3D.box(2,Vec3(1,1,1)),position=p,orientation=q);body.linear_velocity=v;body.angular_velocity=w;body=transform_body(body,variant)
        models.append(add_box_response(gpu,body.position,v=body.linear_velocity,omega=body.angular_velocity,orientation=body.orientation))
    return models^

def decode(values: List[Float64],slot: Int) raises -> RigidBody3D:
    var body=RigidBody3D(MassProperties3D(values[slot+1],Vec3(values[258+slot+1],values[516+slot+1],values[774+slot+1])),Vec3(values[4*258+slot+1],values[5*258+slot+1],values[6*258+slot+1]),Quaternion(values[7*258+slot+1],values[8*258+slot+1],values[9*258+slot+1],values[10*258+slot+1]))
    body.linear_velocity=Vec3(values[11*258+slot+1],values[12*258+slot+1],values[13*258+slot+1]);body.angular_velocity=Vec3(values[14*258+slot+1],values[15*258+slot+1],values[16*258+slot+1]);body.force=Vec3(values[17*258+slot+1],values[18*258+slot+1],values[19*258+slot+1]);body.torque=Vec3(values[20*258+slot+1],values[21*258+slot+1],values[22*258+slot+1]);return body

def snapshot(values: List[Float64],models: List[OracleBox]) raises -> List[OracleBox]:
    var result=models.copy()
    for i in range(len(result)):result[i].body=decode(values,Int(result[i].body_handle.slot))
    return result^
def momentum(models: List[OracleBox]) -> Vec3:
    var result=Vec3(0,0,0)
    for model in models:result=result+model.body.linear_velocity*model.body.properties.mass
    return result
def angular(models: List[OracleBox],entry: List[OracleBox]) -> Vec3:
    var result=Vec3(0,0,0)
    for i in range(len(models)):
        var b=entry[i].body
        result=result+models[i].body.position.cross(b.linear_velocity*b.properties.mass)+b.angular_velocity*b.properties.inertia.x
    return result
def total_mass(models: List[OracleBox]) -> Float64:
    var mass=Float64(0)
    for model in models:mass+=model.body.properties.mass
    return mass

def json_values(values: List[Float64]) -> String:
    var result=String("[")
    for i in range(len(values)):
        if i>0:result+="," 
        result+=String(values[i])
    return result+"]"
def json_models(models: List[OracleBox]) -> String:
    var result=String("[")
    for i in range(len(models)):
        if i>0:result+="," 
        var words=state_words(body_state(models[i].body));result+='{"slot":'+String(models[i].body_handle.slot)+',"words":['
        for j in range(23):
            if j>0:result+="," 
            result+=String(words[j])
        result+="]}"
    return result+"]"

def main() raises:
    var a=argv();assert_equal(len(a),7);var prefix=a[1];var id=Int(a[2]);var hz=Int(a[3]);var policy=Int(a[4]);var seed=Int(a[5]);var variant=Int(a[6])
    var gpu=GpuBoxResponse(velocity_budget=Int32(policy));var models=inputs(gpu,id,seed,variant);var initial=models.copy();var cpu=CpuBoxResponse(policy)
    var dt=Float64(1)/Float64(hz);var g=Vec3(0,0,0) if id==8 else Vec3(0,-9.81,0);var mu=Float64(.2 if id==3 or id==5 or id==8 else .6 if id==4 else 0.0);var e=Float64(.5 if id==6 or id==8 else 0.0)
    var steps=hz if id==6 or id==8 or id==9 else hz//2;var completed=0;var failure_frame=-1;var gpu_error=Int32(0);var cpu_error=Int32(0);var status=String("completed");var check=String("setup")
    var initial_energy=total_kinetic(models)+potential(models,g);var work=Float64(0);var loss=Float64(0);var drift=Float64(0);var orientation=Float64(0);var speed=Float64(0);var depth=Float64(0);var max_sweeps=Int32(0);var max_normal=Float64(0);var max_tangent=Float64(0);var max_energy_error=Float64(0);var max_ratio=Float64(0)
    var created=0;var lost=0;var previous_contact=len(cpu_geometry(models,cpu.conventions))>0;var removal_y=Float64(0);var removal_v=Float64(0);var removed=False;var stale_rollback=False;var failure_stats=List[Float64]();var failure_history=List[Float64]();var fixed_checks=0;var idle_checks=0;var byte_rollback=False
    with open(prefix+"-initial.json","w") as f:f.write('{"bodies":'+json_models(models)+'}\n')
    with open(prefix+"-trace.jsonl","w") as trace:
        for frame in range(steps):
            try:
                if id==7 and frame==hz//8:
                    check="support-removal";var dead=models[0];_=gpu.detection.world.bodies.submit([BodyCommand.remove(dead.body_handle)])
                    var before=gpu.detection.world.bodies.raw();var meta=gpu.detection.world.bodies.metadata()
                    with assert_raises():_=gpu.detection.world.bodies.submit([BodyCommand.update(dead.body_handle,dead.body)])
                    bits_equal(before,gpu.detection.world.bodies.raw());var next=gpu.detection.world.bodies.metadata()
                    for i in range(len(meta)):assert_equal(meta[i],next[i])
                    stale_rollback=True;removal_y=models[1].body.position.y;removal_v=models[1].body.linear_velocity.y;removed=True
                    var active=List[OracleBox]()
                    for i in range(1,len(models)):active.append(models[i])
                    models=active^
                var pre=snapshot(gpu.detection.world.bodies.raw(),models);check="integration"
                assert_equal(gpu.detection.world.bodies.step(dt,g),Int32(0));var raw_entry=gpu.detection.world.bodies.raw();var meta_entry=gpu.detection.world.bodies.metadata();var entry=snapshot(raw_entry,models)
                vector(momentum(entry),momentum(pre)+g*(total_mass(pre)*dt))
                near(total_kinetic(entry)+potential(entry,g),total_kinetic(pre)+potential(pre,g),1e-9)
                for i in range(len(models)):_=models[i].body.integrate(dt,g)
                var expected=CpuBoxResult(List[OracleBox](),List[Float64](),0,0,0,0,0,0,0,0);var cpu_failed=False;var gpu_failed=False;var report=BoxResponseReport(0,0,0,0,0,0,0,0,0,0,0,0)
                try:expected=cpu.solve(models,dt,e,mu,policy,64)
                except:cpu_failed=True
                try:report=gpu.resolve(dt,restitution=e,coefficient=mu,velocity_iterations=Int32(policy),position_iterations=64)
                except:gpu_failed=True
                var raw_after=gpu.detection.world.bodies.raw();var actual=snapshot(raw_after,models);gpu_error=gpu.last_error;cpu_error=cpu.last_error
                if gpu_failed or cpu_failed:
                    failure_frame=frame;status="solver_rejected" if gpu_failed and cpu_failed and gpu_error==cpu_error else "oracle_rejection_disagreement"
                    with gpu._stats.map_to_host() as stats:
                        for i in range(9):failure_stats.append(Float64(stats[i]))
                    failure_history=gpu.residual_history()
                    if gpu_failed:
                        check="response-rollback";bits_equal(raw_entry,raw_after);var meta_after=gpu.detection.world.bodies.metadata()
                        for i in range(len(meta_entry)):assert_equal(meta_entry[i],meta_after[i])
                        byte_rollback=True
                    with open(prefix+"-failure-raw.json","w") as f:f.write('{"entry":'+json_values(raw_entry)+',"after":'+json_values(raw_after)+'}\n')
                    trace.write('{"frame":'+String(frame)+',"gpu_error":'+String(gpu_error)+',"cpu_error":'+String(cpu_error)+',"entry":'+json_models(entry)+',"actual":'+json_models(actual)+',"CPU_normal_residual":'+String(cpu.last_normal_residual)+',"CPU_position_residual":'+String(cpu.last_position_residual)+'}\n')
                    break
                var ratio=Float64(0);var bad_slot=-1;var bad_field=-1
                for i in range(len(actual)):
                    var x=state_words(body_state(actual[i].body));var y=state_words(body_state(expected.models[i].body))
                    for j in range(23):
                        var trial=abs(x[j]-y[j])/(1e-10*(1+abs(y[j])))
                        if trial>ratio:ratio=trial;bad_slot=Int(actual[i].body_handle.slot);bad_field=j
                max_ratio=max(max_ratio,ratio)
                var normal_gate=Float64(0);var tangent_gate=Float64(0)
                with gpu._stats.map_to_host() as stats:normal_gate=Float64(stats[5]);tangent_gate=Float64(stats[6])
                trace.write('{"frame":'+String(frame)+',"actual":'+json_models(actual)+',"entry":'+json_models(entry)+',"expected":'+json_models(expected.models)+',"patches":'+String(report.patches)+',"points":'+String(report.points)+',"sweeps":'+String(report.velocity_sweeps)+',"normal_residual":'+String(report.normal_residual)+',"normal_gate":'+String(normal_gate)+',"tangent_residual":'+String(report.tangent_residual)+',"tangent_gate":'+String(tangent_gate)+',"depth":'+String(report.maximum_depth)+',"state_error_gate_ratio":'+String(ratio)+',"largest_error_slot":'+String(bad_slot)+',"largest_error_field":'+String(bad_field)+'}\n')
                check="independent-state";assert_true(ratio<=1)
                check="response-reports";near(report.kinetic_before,expected.kinetic_before);near(report.kinetic_after,expected.kinetic_after);near(report.maximum_depth,expected.maximum_depth)
                check="residual-depth-energy-cone";assert_true(report.normal_residual<=normal_gate and report.tangent_residual<=tangent_gate);assert_true(report.maximum_depth<=1e-5+1e-9);assert_true(report.maximum_shift<=.25);assert_true(report.kinetic_after<=report.kinetic_before+1e-9*(1+report.kinetic_before))
                with gpu._impulses.map_to_host() as impulse,gpu._tangent.map_to_host() as tangent:
                    for i in range(Int(report.points)):
                        var radius=mu*Float64(impulse[i+1]);var length=sqrt(Float64(tangent[1+i*2])**2+Float64(tangent[2+i*2])**2);assert_true(length<=radius+1e-12*(1+radius));assert_true(impulse[i+1]>=0)
                check="fixed-accumulator-bytes"
                for i in range(len(actual)):
                    var slot=Int(actual[i].body_handle.slot)
                    for field in range(23):
                        if actual[i].body.properties.mass==0 or field>=17:assert_equal(float_bits(raw_entry[field*258+slot+1]),float_bits(raw_after[field*258+slot+1]))
                    if actual[i].body.properties.mass==0:fixed_checks+=1
                if report.patches==0:bits_equal(raw_entry,raw_after);idle_checks+=1
                if report.patches>0 and not previous_contact:created+=1
                if report.patches==0 and previous_contact:lost+=1
                previous_contact=report.patches>0
                if id==8:
                    check="closed-momentum";vector(momentum(actual),momentum(entry));vector(angular(actual,actual),angular(actual,entry))
                if id==6 and created==0:
                    check="analytic-free-flight";var t=Float64(frame+1)*dt;near(actual[1].body.position.y,.7-.5*9.81*t*t);near(actual[1].body.linear_velocity.y,-9.81*t)
                if id==6 and report.patches>0 and entry[1].body.linear_velocity.y<-.2:
                    check="analytic-restitution";near(actual[1].body.linear_velocity.y,-e*entry[1].body.linear_velocity.y)
                if id==7 and removed:
                    check="analytic-support-free-flight";var t=Float64(frame-hz//8+1)*dt;near(actual[0].body.position.y,removal_y+removal_v*t-.5*9.81*t*t);near(actual[0].body.linear_velocity.y,removal_v-9.81*t);assert_equal(report.patches,Int32(0))
                check="energy-work-accounting";work+=potential(actual,g)-potential(entry,g);loss+=total_kinetic(entry)-total_kinetic(actual)
                var accounted=abs(total_kinetic(actual)+potential(actual,g)-initial_energy-work+loss);max_energy_error=max(max_energy_error,accounted);assert_true(accounted<=1e-9*(1+abs(initial_energy)+abs(work)+abs(loss)))
                depth=max(depth,report.maximum_depth);max_sweeps=max(max_sweeps,report.velocity_sweeps);max_normal=max(max_normal,report.normal_residual);max_tangent=max(max_tangent,report.tangent_residual)
                if id==0 or id==1 or id==5 or id==10:
                    for i in range(len(actual)):
                        if actual[i].body.properties.mass==0:continue
                        var before=initial[Int(actual[i].body_handle.slot)].body;var now=actual[i].body
                        drift=max(drift,(now.position-before.position).length())
                        for axis in [Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,1)]:orientation=max(orientation,(now.orientation.rotate(axis)-before.orientation.rotate(axis)).length())
                        if frame>=3*steps//4:speed=max(speed,max(now.linear_velocity.length(),now.angular_velocity.length()))
                    check="rest-drift-orientation-jitter";assert_true(drift<=1e-4 and orientation<=1e-3 and speed<=1e-3)
                models=expected.models.copy();completed+=1
            except error:
                print("INTERACTION_CHECK_FAILURE",id,hz,policy,seed,variant,frame,check,error);failure_frame=frame;status="check_failure";break
    if completed==steps:
        if (id==6 or id==8) and (created==0 or lost==0):status="event_coverage_failure";check="creation-and-loss"
        if id==7 and (not removed or not stale_rollback or lost==0):status="event_coverage_failure";check="support-removal"
        if id==9 and lost==0:status="event_coverage_failure";check="ledge-exit"
    with open(prefix+"-result.json","w") as f:f.write('{"status":"'+status+'","id":'+String(id)+',"hz":'+String(hz)+',"policy":'+String(policy)+',"seed":'+String(seed)+',"variant":'+String(variant)+',"requested_steps":'+String(steps)+',"completed_steps":'+String(completed)+',"failure_frame":'+String(failure_frame)+',"failure_check":"'+check+'","gpu_error":'+String(gpu_error)+',"cpu_error":'+String(cpu_error)+',"failure_stats":'+json_values(failure_stats)+',"failure_normal_history":'+json_values(failure_history)+',"maximum_depth":'+String(depth)+',"maximum_rest_displacement":'+String(drift)+',"maximum_rest_basis_change":'+String(orientation)+',"settled_jitter":'+String(speed)+',"maximum_sweeps":'+String(max_sweeps)+',"maximum_normal_residual":'+String(max_normal)+',"maximum_tangent_residual":'+String(max_tangent)+',"maximum_independent_state_gate_ratio":'+String(max_ratio)+',"projection_work":'+String(work)+',"kinetic_dissipation":'+String(loss)+',"maximum_energy_accounting_error":'+String(max_energy_error)+',"contact_created":'+String(created)+',"contact_lost":'+String(lost)+',"fixed_byte_checks":'+String(fixed_checks)+',"no_contact_byte_checks":'+String(idle_checks)+',"response_rollback":'+("true" if byte_rollback else "false")+',"stale_update_rollback":'+("true" if stale_rollback else "false")+'}\n')
    print("INTERACTION_RESULT",id,hz,policy,seed,variant,status,"completed",completed,"failure",failure_frame,"GPU_CPU",gpu_error,cpu_error,"check",check,"state_ratio",max_ratio,"events",created,lost)
    gpu.close()
