"""Separate resolved-sign translation fixtures; strict original failure is retained."""
from std.collections import List
from std.testing import assert_equal,assert_true,assert_raises
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3
from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse,cpu_geometry
from experimental.physics_gpu.test_coupled_helpers import add_box_coupled
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.lifecycle import body_state,state_words
from experimental.physics_gpu.test_box_interactions import snapshot,json_models,json_values,momentum,angular
from experimental.physics_gpu.test_box_response import near,vector,bits_equal,total_kinetic
from experimental.physics_gpu.box_box import float_bits

def metadata_equal(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def main() raises:
    var args=argv();assert_equal(len(args),7);var prefix=args[1];var dynamic=Int(args[2])==1;var h=Float64(args[3]);var translation=Float64(args[4]);var sign=Int(args[5]);var hz=Int(args[6])
    var dt=Float64(1)/Float64(hz);var gap=Float64(.107) if dynamic else h*Float64(sign)/65536
    var offset=Vec3(translation,translation/2,-translation/4);var distance=h+gap/2
    var gpu=GpuCoupledBoxResponse(velocity_budget=96);var models: List[OracleBox]=[add_box_coupled(gpu,offset+Vec3(-distance,0,0),Vec3(h,h,h),v=Vec3(.5,0,0)),add_box_coupled(gpu,offset+Vec3(distance,0,0),Vec3(h,h,h),v=Vec3(-.5,0,0))]
    var cpu=CpuCoupledBoxResponse(96);var initial=models.copy();var anchor=models.copy();var steps=hz*3//10 if dynamic else 1
    var initial_energy=total_kinetic(models);near(initial_energy,.5)
    var before=gpu.detection.world.bodies.raw();var meta=gpu.detection.world.bodies.metadata()
    with assert_raises():_=gpu.resolve(dt,coefficient=-1,velocity_iterations=96,position_iterations=64)
    bits_equal(before,gpu.detection.world.bodies.raw());metadata_equal(meta,gpu.detection.world.bodies.metadata())
    var created=0;var ended=0;var previous=False;var first_frame=-1;var end_frame=-1;var no_contact=0;var max_ratio=Float64(0);var max_energy_error=Float64(0);var loss=Float64(0);var max_depth=Float64(0)
    with open(prefix+"-initial.json","w") as f:f.write('{"bodies":'+json_models(initial)+',"half":'+String(h)+',"translation":'+json_values([offset.x,offset.y,offset.z])+',"prescribed_gap":'+String(gap)+'}\n')
    with open(prefix+"-trace.jsonl","w") as trace:
        for frame in range(steps):
            if dynamic:
                assert_equal(gpu.detection.world.bodies.step(dt,Vec3(0,0,0)),Int32(0))
                for i in range(len(models)):_=models[i].body.integrate(dt,Vec3(0,0,0))
            var raw_entry=gpu.detection.world.bodies.raw();var entry=snapshot(raw_entry,models)
            var signed_gap=entry[1].body.position.x-entry[0].body.position.x-2*h
            var present=signed_gap<=0;var analytic_present=sign<=0 if not dynamic else frame==hz*107//1000
            assert_equal(present,analytic_present)
            if not dynamic:near(signed_gap,gap)
            if dynamic:
                assert_true(abs(signed_gap)>1.0/68719476736)
                if first_frame<0:
                    for i in range(2):vector(entry[i].body.position,initial[i].body.position+initial[i].body.linear_velocity*(Float64(frame+1)*dt))
            var detected=gpu.detection.detect();var independent=cpu_geometry(entry,cpu.conventions)
            assert_equal(len(detected.patches),1 if present else 0);assert_equal(len(independent),len(detected.patches))
            if present:
                assert_equal(len(detected.patches[0].points),4);near(detected.patches[0].separation,signed_gap);near(independent[0].gap,signed_gap);vector(detected.patches[0].normal,Vec3(1,0,0))
            var expected=cpu.solve(models,dt,.5,.2,96,64);var report=gpu.resolve(dt,restitution=.5,coefficient=.2,velocity_iterations=96,position_iterations=64)
            var raw_after=gpu.detection.world.bodies.raw();var actual=snapshot(raw_after,models);var ratio=Float64(0)
            for i in range(2):
                var a=state_words(body_state(actual[i].body));var b=state_words(body_state(expected.models[i].body))
                for j in range(23):ratio=max(ratio,abs(a[j]-b[j])/(1e-10*(1+abs(b[j]))))
                for field in range(17,23):assert_equal(float_bits(raw_entry[field*258+i+1]),float_bits(raw_after[field*258+i+1]))
                vector(actual[i].body.angular_velocity,Vec3(0,0,0));near(actual[i].body.orientation.w,1);near(actual[i].body.orientation.x,0);near(actual[i].body.orientation.y,0);near(actual[i].body.orientation.z,0)
            assert_true(ratio<=1);max_ratio=max(max_ratio,ratio)
            near(report.kinetic_before,expected.kinetic_before);near(report.kinetic_after,expected.kinetic_after);near(report.maximum_depth,expected.maximum_depth)
            assert_equal(report.patches,Int32(1 if present else 0));assert_equal(report.points,Int32(4 if present else 0))
            var normal_gate=Float64(0);var tangent_gate=Float64(0)
            with gpu._stats.map_to_host() as stats:normal_gate=Float64(stats[5]);tangent_gate=Float64(stats[6])
            assert_true(report.normal_residual<=normal_gate and report.tangent_residual<=tangent_gate);assert_true(report.maximum_depth<=1e-5+1e-9 and report.maximum_shift<=.25);assert_true(report.kinetic_after<=report.kinetic_before+1e-9*(1+report.kinetic_before))
            var impulse_sum=Float64(0);var impulse_values=List[Float64]();var tangent_values=List[Float64]()
            with gpu._impulses.map_to_host() as impulses,gpu._tangent.map_to_host() as tangents:
                for i in range(Int(report.points)):
                    var p=Float64(impulses[i+1]);var t=sqrt(Float64(tangents[1+i*2])**2+Float64(tangents[2+i*2])**2)
                    assert_true(p>=0 and t<=.2*p+1e-12*(1+.2*p));assert_true(t<=1e-12);impulse_sum+=p;impulse_values.append(p);tangent_values.append(Float64(tangents[1+i*2]));tangent_values.append(Float64(tangents[2+i*2]))
            vector(momentum(actual),momentum(entry));vector(angular(actual,actual),angular(actual,entry))
            if present:
                assert_true(first_frame<0);first_frame=frame;created+=1;anchor=actual.copy();near(impulse_sum,1.5);near(report.kinetic_before,.5);near(report.kinetic_after,.125)
                vector(actual[0].body.linear_velocity,Vec3(-.25,0,0));vector(actual[1].body.linear_velocity,Vec3(.25,0,0))
            elif first_frame<0:
                bits_equal(raw_entry,raw_after);no_contact+=1
                vector(actual[0].body.linear_velocity,Vec3(.5,0,0));vector(actual[1].body.linear_velocity,Vec3(-.5,0,0))
            else:
                bits_equal(raw_entry,raw_after);no_contact+=1
                for i in range(2):
                    vector(actual[i].body.position,anchor[i].body.position+anchor[i].body.linear_velocity*(Float64(frame-first_frame)*dt));vector(actual[i].body.linear_velocity,anchor[i].body.linear_velocity)
            if previous and not present:ended+=1;end_frame=frame
            previous=present;loss+=total_kinetic(entry)-total_kinetic(actual)
            var energy_error=abs(total_kinetic(actual)-initial_energy+loss);assert_true(energy_error<=1e-9*(1+initial_energy+abs(loss)));max_energy_error=max(max_energy_error,energy_error);max_depth=max(max_depth,report.maximum_depth)
            trace.write('{"frame":'+String(frame)+',"time":'+String(Float64(frame+1)*dt if dynamic else Float64(0))+',"entry":'+json_models(entry)+',"actual":'+json_models(actual)+',"expected":'+json_models(expected.models)+',"signed_gap":'+String(signed_gap)+',"patches":'+String(report.patches)+',"points":'+String(report.points)+',"normal_impulses":'+json_values(impulse_values)+',"tangent_impulses":'+json_values(tangent_values)+',"normal_residual":'+String(report.normal_residual)+',"normal_gate":'+String(normal_gate)+',"tangent_residual":'+String(report.tangent_residual)+',"tangent_gate":'+String(tangent_gate)+',"depth":'+String(report.maximum_depth)+',"state_gate_ratio":'+String(ratio)+',"kinetic_before":'+String(report.kinetic_before)+',"kinetic_after":'+String(report.kinetic_after)+',"kinetic_loss":'+String(loss)+',"projection_work":0,"energy_error":'+String(energy_error)+'}\n')
            models=expected.models.copy()
    if dynamic:assert_equal(first_frame,hz*107//1000);assert_equal(created,1);assert_equal(ended,1);assert_equal(end_frame,first_frame+1)
    else:assert_equal(created,1 if sign<=0 else 0)
    with open(prefix+"-result.json","w") as f:f.write('{"status":"passed","steps":'+String(steps)+',"created":'+String(created)+',"ended":'+String(ended)+',"first_frame":'+String(first_frame)+',"end_frame":'+String(end_frame)+',"no_contact_byte_checks":'+String(no_contact)+',"invalid_configuration_rollback":true,"accumulator_bytes_checked":true,"max_state_gate_ratio":'+String(max_ratio)+',"max_energy_error":'+String(max_energy_error)+',"max_depth":'+String(max_depth)+'}\n')
    print("TRANSLATION_BOUNDARY",h,translation,sign,hz,"steps",steps,"first",first_frame,"state ratio",max_ratio);gpu.close()
