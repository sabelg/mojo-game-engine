"""Original friction rejection and separate opt-in coupled policy analytic checks."""
from std.collections import List
from std.math import sqrt
from std.testing import assert_equal,assert_true,assert_raises
from std.sys import argv
from std.ffi import external_call
from std.memory import Pointer
from mojo_game import Vec3
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.box_response import GpuBoxResponse
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse
from experimental.physics_gpu.lifecycle import body_state,state_words
from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse
from experimental.physics_gpu.test_coupled_helpers import add_box_coupled
from experimental.physics_gpu.test_box_interactions import inputs,snapshot,json_models,json_values
from experimental.physics_gpu.test_box_response import bits_equal,near,total_kinetic,potential,vector

@fieldwise_init
struct Tick(ImplicitlyCopyable,Movable):
    var seconds: Int64
    var nanos: Int64
def clock_seconds() -> Float64:
    var t=Tick(0,0);_=external_call["clock_gettime",Int32](Int32(1),Pointer(to=t));return Float64(t.seconds)+Float64(t.nanos)*1e-9

def main() raises:
    var args=argv();var output=args[1]
    var old=GpuBoxResponse(velocity_budget=96);_=inputs(old,3,17,0);var began=clock_seconds();assert_equal(old.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0));var before=old.detection.world.bodies.raw()
    with assert_raises():_=old.resolve(1.0/30,coefficient=.2,velocity_iterations=96,position_iterations=64)
    var old_wall=clock_seconds()-began;assert_equal(old.last_error,Int32(114));bits_equal(before,old.detection.world.bodies.raw())
    with old._stats.map_to_host() as stats:near(Float64(stats[2]),3.69438989357356e-7,1e-14);near(Float64(stats[7]),8.533027288225932e-6,1e-14)
    old.close()
    for variant in range(3):
        var gpu=GpuCoupledBoxResponse(velocity_budget=96)
        var models: List[OracleBox]=[add_box_coupled(gpu,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_coupled(gpu,Vec3(0,.5-1e-5,0),v=Vec3(.3,0,.05)),add_box_coupled(gpu,Vec3(.03,1.5-2e-5,0),v=Vec3(.3,0,.05))]
        var c=Float64(1) if variant==0 else sqrt(Float64(.5)) if variant==1 else Float64(0);var s=Float64(0) if variant==0 else sqrt(Float64(.5)) if variant==1 else Float64(1)
        began=clock_seconds();assert_equal(gpu.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0));var entry=gpu.detection.world.bodies.raw();var entry_bodies=snapshot(entry,models)
        var report=gpu.resolve(1.0/30,coefficient=.2,velocity_iterations=96,position_iterations=64,basis_cos=c,basis_sin=s);var wall=clock_seconds()-began;var after=gpu.detection.world.bodies.raw();var actual=snapshot(after,models)
        var speed=sqrt(.3*.3+.05*.05);var d=Vec3(.3/speed,0,.05/speed);var expected=Vec3(.3,0,.05)-d*(.2*9.81/30)
        for i in range(1,3):
            vector(actual[i].body.linear_velocity,expected);vector(actual[i].body.angular_velocity,Vec3(0,0,0));near(actual[i].body.properties.inertia.x,4.0/3)
        near(report.kinetic_before,.398858);near(report.kinetic_after,.11399178610369927);assert_true(report.maximum_depth<=1e-5+1e-9);assert_equal(report.velocity_sweeps,Int32(96))
        # Independent input-based replay: scalar unit-response matrices, RREF
        # normal operators, spectral disks and complete-pivot Newton correction.
        for i in range(len(models)):_=models[i].body.integrate(1.0/30,Vec3(0,-9.81,0))
        var cpu=CpuCoupledBoxResponse(96);var replay=cpu.solve(models,1.0/30,0,.2,96,64)
        for i in range(len(models)):
            var x=state_words(body_state(actual[i].body));var y=state_words(body_state(replay.models[i].body))
            for field in range(23):near(x[field],y[field])
        near(report.kinetic_before,replay.kinetic_before);near(report.kinetic_after,replay.kinetic_after);near(report.maximum_depth,replay.maximum_depth)
        var normal_gate=Float64(0);var tangent_gate=Float64(0)
        with gpu._stats.map_to_host() as stats:normal_gate=Float64(stats[5]);tangent_gate=Float64(stats[6])
        assert_true(report.normal_residual<=normal_gate and report.tangent_residual<=tangent_gate)
        var geometry=List[Float64]()
        with gpu._geometry.map_to_host() as values:
            for i in range(81):geometry.append(Float64(values[i]))
        var normals=List[Float64]();var tangent=List[Float64]();var floor_load=Float64(0);var upper_load=Float64(0)
        with gpu._impulses.map_to_host() as values:
            for i in range(8):
                normals.append(Float64(values[i+1]))
                if i<4:floor_load+=Float64(values[i+1])
                else:upper_load+=Float64(values[i+1])
        with gpu._tangent.map_to_host() as values:
            for i in range(16):tangent.append(Float64(values[i+1]))
        near(floor_load,1.308);near(upper_load,.654)
        var lo=actual[1].body;var up=actual[2].body;var yfloor=(geometry[6]+geometry[9])*.5;var yupper=(geometry[46]+geometry[49])*.5
        var hf=lo.position.y-yfloor;var hu=up.position.y-yupper;var hl=yupper-lo.position.y
        var copu=up.position+d*(.2*hu);var copf=lo.position+(copu-lo.position)*.5+d*(.2*(hf+.5*hl))
        for patch in range(2):
            var left=(geometry[1+patch*40+4]+geometry[1+patch*40+7])*.5;var right=(geometry[1+(patch*4+2)*10+4]+geometry[1+(patch*4+2)*10+7])*.5
            var za=(geometry[1+patch*40+6]+geometry[1+patch*40+9])*.5;var zb=(geometry[1+(patch*4+1)*10+6]+geometry[1+(patch*4+1)*10+9])*.5
            var center=Vec3((left+right)*.5,0,(za+zb)*.5);var cop=copf if patch==0 else copu;var load=1.308 if patch==0 else .654
            for j in range(4):
                var g=1+(patch*4+j)*10;var p=Vec3((geometry[g+4]+geometry[g+7])*.5,0,(geometry[g+6]+geometry[g+9])*.5)
                var ax=(right-left)*.5;var az=(zb-za)*.5;var analytic=load*.25*(1+((p.x-center.x)/ax)*((cop.x-center.x)/ax)+((p.z-center.z)/az)*((cop.z-center.z)/az));near(normals[patch*4+j],analytic)
                var radius=.2*normals[patch*4+j];assert_true(sqrt(tangent[(patch*4+j)*2]**2+tangent[(patch*4+j)*2+1]**2)<=radius+1e-12*(1+radius))
        var w=gpu.work_report();var work=List[Float64]()
        for i in range(10):work.append(Float64(w[i]))
        var f=output+"-basis-"+String(variant)+".json"
        with open(f,"w") as file:file.write('{"status":"passed","basis":'+String(variant)+',"outer_sweeps":'+String(report.velocity_sweeps)+',"normal_residual":'+String(report.normal_residual)+',"normal_gate":'+String(normal_gate)+',"tangent_residual":'+String(report.tangent_residual)+',"tangent_gate":'+String(tangent_gate)+',"depth":'+String(report.maximum_depth)+',"kinetic_before":'+String(report.kinetic_before)+',"kinetic_after":'+String(report.kinetic_after)+',"projection_work":'+String(potential(actual,Vec3(0,-9.81,0))-potential(entry_bodies,Vec3(0,-9.81,0)))+',"kinetic_dissipation":'+String(total_kinetic(entry_bodies)-total_kinetic(actual))+',"work_counters":'+json_values(work)+',"entry":'+json_models(entry_bodies)+',"actual":'+json_models(actual)+',"normal_impulses":'+json_values(normals)+',"tangent_impulses":'+json_values(tangent)+',"sync_step_response_host_wall_s":'+String(wall)+',"original96_failed_host_wall_s":'+String(old_wall)+',"independent_CPU_replay":true,"original_rejection_retained":true,"real_time_or_speedup_claim":false}\n')
        print("COUPLED_TARGET",variant,"normal",report.normal_residual,"tangent",report.tangent_residual,"work",work,"wall",wall);gpu.close()
