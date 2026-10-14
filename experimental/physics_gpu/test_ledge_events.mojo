"""Separate generation-safe ledge transitions; original event gaps stay historical."""
from std.collections import List
from std.testing import assert_equal,assert_true,assert_raises
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,RigidBody3D
from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse,cpu_geometry
from experimental.physics_gpu.test_coupled_helpers import add_box_coupled
from experimental.physics_gpu.box_oracle import OracleBox,box_corners_bounds
from experimental.physics_gpu.collision import PairKey,BoxCommand
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.test_box_interactions import snapshot,json_models,json_values,momentum,total_mass
from experimental.physics_gpu.test_box_response import near,vector,bits_equal,total_kinetic,potential
from experimental.physics_gpu.box_box import float_bits

def json_bool(value: Bool) -> String:return String("true") if value else String("false")

def key_json(k: PairKey) -> String:
    return "["+String(k.a.slot)+","+String(k.a.generation)+","+String(k.revision_a)+","+String(k.body_a.slot)+","+String(k.body_a.generation)+","+String(k.b.slot)+","+String(k.b.generation)+","+String(k.revision_b)+","+String(k.body_b.slot)+","+String(k.body_b.generation)+"]"
def same_key(a: PairKey,b: PairKey) raises:
    assert_equal(key_json(a),key_json(b));assert_equal(a.a.owner,b.a.owner);assert_equal(a.b.owner,b.b.owner);assert_equal(a.body_a.owner,b.body_a.owner);assert_equal(a.body_b.owner,b.body_b.owner)
def valid_key(k: PairKey,a: OracleBox,b: OracleBox) raises:
    assert_equal(k.a.slot,a.shape.slot);assert_equal(k.a.generation,a.shape.generation);assert_equal(k.a.owner,a.shape.owner);assert_equal(k.revision_a,a.revision)
    assert_equal(k.b.slot,b.shape.slot);assert_equal(k.b.generation,b.shape.generation);assert_equal(k.b.owner,b.shape.owner);assert_equal(k.revision_b,b.revision)
    assert_equal(k.body_a.slot,a.body_handle.slot);assert_equal(k.body_a.generation,a.body_handle.generation);assert_equal(k.body_a.owner,a.body_handle.owner)
    assert_equal(k.body_b.slot,b.body_handle.slot);assert_equal(k.body_b.generation,b.body_handle.generation);assert_equal(k.body_b.owner,b.body_handle.owner)
def registry_equal(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def main() raises:
    var args=argv();assert_equal(len(args),5);var prefix=args[1];var kind=Int(args[2]);var hz=Int(args[3]);var policy=Int(args[4]);assert_true(kind>=0 and kind<=2)
    var dt=Float64(1)/Float64(hz);var steps=hz*3//5 if kind!=1 else hz*7//10;var removal_frame=hz//5
    var gpu=GpuCoupledBoxResponse(velocity_budget=Int32(policy));var models: List[OracleBox]=[add_box_coupled(gpu,Vec3(0,-.25,0),Vec3(.5,.25,1),0),add_box_coupled(gpu,Vec3(Float64(0) if kind==0 else Float64(.29),.49999,0),v=Vec3(Float64(0 if kind==0 else 2 if kind==1 else 4),0,0))]
    var cpu=CpuCoupledBoxResponse(policy);var initial=models.copy();var g=Vec3(0,0,0) if kind==1 else Vec3(0,-9.81,0);var initial_energy=total_kinetic(models)+potential(models,g)
    var start=gpu.detection.detect();assert_equal(len(start.patches),1);valid_key(start.patches[0].key,models[0],models[1]);var old_key=start.patches[0].key;var previous_key=old_key;var epoch=start.epoch
    assert_equal(len(cpu_geometry(models,cpu.conventions)),1)
    var previous=True;var ended=False;var ending_time=Float64(-1);var ending_frame=-1;var persistent=0;var end_count=0;var generation_reused=False;var stale_rollback=False
    var anchor=models[1].body;var work=Float64(0);var loss=Float64(0);var field_work=Float64(0);var energy_error=Float64(0);var max_ratio=Float64(0);var max_depth=Float64(0);var max_normal=Float64(0);var free_frames=0;var no_contact_bytes=0;var minimum_exit_vx=Float64(4);var minimum_normal_x=Float64(0);var minimum_projection_x=Float64(0);var latest_overlap=Float64(0)
    var force_gate=Float64(1e-10)
    with open(prefix+"-initial.json","w") as f:f.write('{"bodies":'+json_models(models)+',"initial_pair":'+key_json(old_key)+',"owner_verified":true}\n')
    with open(prefix+"-events.jsonl","w") as events,open(prefix+"-trace.jsonl","w") as trace:
        events.write('{"event":"begin","time":0,"pair":'+key_json(old_key)+',"owner_verified":true}\n')
        for frame in range(steps):
            var time=Float64(frame+1)*dt
            if kind==0 and frame==removal_frame:
                var dead=models[0];anchor=models[1].body
                _=gpu.detection.world.bodies.submit([BodyCommand.remove(dead.body_handle)])
                var absent=gpu.detection.detect();assert_true(absent.epoch>epoch);epoch=absent.epoch;assert_equal(len(absent.patches),0)
                var before=gpu.detection.world.bodies.raw();var meta=gpu.detection.world.bodies.metadata();var reg=gpu.detection.world.debug_registry()
                with assert_raises():_=gpu.detection.world.bodies.submit([BodyCommand.update(dead.body_handle,dead.body)])
                bits_equal(before,gpu.detection.world.bodies.raw());registry_equal(meta,gpu.detection.world.bodies.metadata())
                with assert_raises():_=gpu.detection.world.submit_boxes([BoxCommand.detach(dead.shape)])
                bits_equal(before,gpu.detection.world.bodies.raw());registry_equal(meta,gpu.detection.world.bodies.metadata());var reg_after=gpu.detection.world.debug_registry();registry_equal(reg[0],reg_after[0]);bits_equal(reg[1],reg_after[1]);stale_rollback=True
                var replacement=add_box_coupled(gpu,Vec3(-3,-.25,0),Vec3(.5,.25,1),0)
                assert_equal(replacement.body_handle.slot,dead.body_handle.slot);assert_equal(replacement.body_handle.generation,dead.body_handle.generation+1);assert_equal(replacement.shape.slot,dead.shape.slot);assert_equal(replacement.shape.generation,dead.shape.generation+1);assert_equal(replacement.shape.owner,dead.shape.owner)
                models[0]=replacement;generation_reused=True;ended=True;previous=False;end_count+=1;ending_time=Float64(frame)*dt;ending_frame=frame
                events.write('{"event":"ended","mechanism":"support-removal","time":'+String(ending_time)+',"pair":'+key_json(old_key)+',"owner_verified":true,"generation_reused":true}\n')
            var pre=snapshot(gpu.detection.world.bodies.raw(),models)
            var next_g=Vec3(0,-9.81,0) if kind!=1 or ended else Vec3(0,0,0)
            field_work+=potential(pre,next_g)-potential(pre,g);g=next_g
            assert_equal(gpu.detection.world.bodies.step(dt,g),Int32(0));var raw_entry=gpu.detection.world.bodies.raw();var entry=snapshot(raw_entry,models)
            vector(momentum(entry),momentum(pre)+g*(total_mass(pre)*dt));near(total_kinetic(entry)+potential(entry,g),total_kinetic(pre)+potential(pre,g),1e-9)
            for i in range(len(models)):_=models[i].body.integrate(dt,g)
            var expected=cpu.solve(models,dt,0,0,policy,64);var report=gpu.resolve(dt,coefficient=0,velocity_iterations=Int32(policy),position_iterations=64)
            var raw_after=gpu.detection.world.bodies.raw();var actual=snapshot(raw_after,models);var ratio=Float64(0)
            for i in range(len(actual)):
                var x=state_words(body_state(actual[i].body));var y=state_words(body_state(expected.models[i].body))
                for j in range(23):ratio=max(ratio,abs(x[j]-y[j])/(1e-10*(1+abs(y[j]))))
            assert_true(ratio<=1);max_ratio=max(max_ratio,ratio);near(report.kinetic_before,expected.kinetic_before);near(report.kinetic_after,expected.kinetic_after);near(report.maximum_depth,expected.maximum_depth)
            var normal_gate=Float64(0);var tangent_gate=Float64(0)
            with gpu._stats.map_to_host() as stats:normal_gate=Float64(stats[5]);tangent_gate=Float64(stats[6])
            assert_true(report.normal_residual<=normal_gate and report.tangent_residual<=tangent_gate);assert_true(report.maximum_depth<=1e-5+1e-9);assert_true(report.maximum_shift<=.25);assert_true(report.kinetic_after<=report.kinetic_before+1e-9*(1+report.kinetic_before))
            with gpu._impulses.map_to_host() as impulses,gpu._tangent.map_to_host() as tangents:
                for i in range(Int(report.points)):assert_true(impulses[i+1]>=0);assert_true(sqrt(Float64(tangents[1+i*2])**2+Float64(tangents[2+i*2])**2)<=1e-12)
            for i in range(len(actual)):
                var slot=Int(actual[i].body_handle.slot)
                for f in range(23):
                    if actual[i].body.properties.mass==0 or f>=17:assert_equal(float_bits(raw_entry[f*258+slot+1]),float_bits(raw_after[f*258+slot+1]))
            if report.patches==0:bits_equal(raw_entry,raw_after);no_contact_bytes+=1
            var detected=gpu.detection.detect();assert_true(detected.epoch>epoch);epoch=detected.epoch;assert_equal(len(detected.patches),Int(report.patches));var independent=cpu_geometry(expected.models,cpu.conventions);assert_equal(len(independent),len(detected.patches));assert_true(len(detected.patches)<=1)
            var present=len(detected.patches)>0;var now=actual[1].body;var bounds=box_corners_bounds(actual[1]);latest_overlap=.5-bounds[0].x
            if present:
                assert_true(not ended);valid_key(detected.patches[0].key,models[0],models[1]);same_key(detected.patches[0].key,previous_key);same_key(detected.patches[0].key,old_key);previous_key=detected.patches[0].key;vector(detected.patches[0].normal,independent[0].normal)
                events.write('{"event":"persistent","time":'+String(time)+',"pair":'+key_json(previous_key)+',"owner_verified":true}\n');persistent+=1
            if previous and not present:
                ended=True;ending_time=time;ending_frame=frame;anchor=now;end_count+=1
                events.write('{"event":"ended","mechanism":"lateral-separation","time":'+String(time)+',"previous_time":'+String(time-dt)+',"pair":'+key_json(previous_key)+',"owner_verified":true}\n')
            previous=present
            if kind==1:
                near(now.position.x,.29+2*time);near(now.linear_velocity.x,2);vector(now.angular_velocity,Vec3(0,0,0));near(now.orientation.w,1);near(now.orientation.x,0);near(now.orientation.y,0);near(now.orientation.z,0)
                assert_equal(present,.29+2*time<=1)
                if not ended:near(now.position.y,.49999);near(now.linear_velocity.y,0)
                if ended:
                    assert_true(bounds[0].x>.5)
                    var elapsed=time-ending_time;vector(now.position,anchor.position+anchor.linear_velocity*elapsed+Vec3(0,-9.81,0)*(.5*elapsed*elapsed));vector(now.linear_velocity,anchor.linear_velocity+Vec3(0,-9.81,0)*elapsed);free_frames+=1
            elif kind==0 and ended:
                var elapsed=time-ending_time;vector(now.position,anchor.position+anchor.linear_velocity*elapsed+g*(.5*elapsed*elapsed));vector(now.linear_velocity,anchor.linear_velocity+g*elapsed);vector(now.angular_velocity,anchor.angular_velocity);assert_true(not present);free_frames+=1
            elif kind==2:
                if not ended:
                    var axes_x=now.orientation.rotate(Vec3(1,0,0));var axes_y=now.orientation.rotate(Vec3(0,1,0));assert_true(axes_x.x>=.877 and axes_x.y<=1e-10 and axes_y.x>=-1e-10 and axes_y.y>=.877);assert_true(abs(now.orientation.x)<=1e-8 and abs(now.orientation.y)<=1e-8)
                    var nx=detected.patches[0].normal.x;assert_true(nx>=-1e-12 and independent[0].normal.x>=-1e-12);minimum_normal_x=min(minimum_normal_x,nx)
                    var shift=now.position.x-entry[1].body.position.x;assert_true(shift>=-1e-10);minimum_projection_x=min(minimum_projection_x,shift)
                assert_true(now.linear_velocity.x>=4-1e-10);assert_true(now.position.x>=.29+4*time-1e-10);minimum_exit_vx=min(minimum_exit_vx,now.linear_velocity.x)
                if ended:
                    var elapsed=time-ending_time;vector(now.position,anchor.position+anchor.linear_velocity*elapsed+g*(.5*elapsed*elapsed));vector(now.linear_velocity,anchor.linear_velocity+g*elapsed);vector(now.angular_velocity,anchor.angular_velocity);assert_true(not present);free_frames+=1
            work+=potential(actual,g)-potential(entry,g);loss+=total_kinetic(entry)-total_kinetic(actual);var accounted=abs(total_kinetic(actual)+potential(actual,g)-initial_energy-field_work-work+loss);energy_error=max(energy_error,accounted);assert_true(accounted<=1e-9*(1+abs(initial_energy)+abs(work)+abs(loss)+abs(field_work)))
            max_depth=max(max_depth,report.maximum_depth);max_normal=max(max_normal,report.normal_residual)
            trace.write('{"frame":'+String(frame)+',"time":'+String(time)+',"gravity":'+json_values([g.x,g.y,g.z])+',"actual":'+json_models(actual)+',"entry":'+json_models(entry)+',"expected":'+json_models(expected.models)+',"patches":'+String(report.patches)+',"points":'+String(report.points)+',"normal_residual":'+String(report.normal_residual)+',"normal_gate":'+String(normal_gate)+',"depth":'+String(report.maximum_depth)+',"state_gate_ratio":'+String(ratio)+',"left_extent_x":'+String(bounds[0].x)+',"rightward_sphere_clearance":'+String(now.position.x-.5-sqrt(Float64(3))*.5)+',"field_work":'+String(field_work)+',"projection_work":'+String(work)+',"kinetic_loss":'+String(loss)+',"energy_accounting_error":'+String(accounted)+'}\n')
            models=expected.models.copy()
    assert_true(ended and end_count==1 and persistent>0 and free_frames>0)
    if kind==0:near(ending_time,.2);assert_true(stale_rollback and generation_reused)
    if kind==1:near(ending_time,Float64(11)/30)
    if kind==2:assert_true(ending_time<=.3+1e-12)
    with open(prefix+"-result.json","w") as f:f.write('{"status":"passed","kind":'+String(kind)+',"hz":'+String(hz)+',"policy":'+String(policy)+',"duration":'+String(Float64(steps)*dt)+',"completed_steps":'+String(steps)+',"ending_time":'+String(ending_time)+',"ending_frame":'+String(ending_frame)+',"persistent_observations":'+String(persistent)+',"ended_observations":'+String(end_count)+',"free_fall_frames":'+String(free_frames)+',"no_contact_byte_checks":'+String(no_contact_bytes)+',"generation_reused":'+json_bool(generation_reused)+',"stale_rollback":'+json_bool(stale_rollback)+',"max_state_gate_ratio":'+String(max_ratio)+',"max_depth":'+String(max_depth)+',"max_normal_residual":'+String(max_normal)+',"max_energy_accounting_error":'+String(energy_error)+',"minimum_exit_vx":'+String(minimum_exit_vx)+',"minimum_normal_x":'+String(minimum_normal_x)+',"minimum_projection_x":'+String(minimum_projection_x)+',"field_work":'+String(field_work)+',"projection_work":'+String(work)+',"kinetic_loss":'+String(loss)+',"final_horizontal_overlap":'+String(latest_overlap)+'}\n')
    print("LEDGE_EVENT",kind,hz,policy,"ending time",ending_time,"frame",ending_frame,"full steps",steps,"state ratio",max_ratio,"energy error",energy_error);gpu.close()
