"""First independent analytic sliding/stopping gate; record before failure."""
from std.collections import List,Array
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,RigidBody3D,MassProperties3D
from experimental.physics_gpu.temporal_floor_friction import GpuTemporalFloorFrictionAdvance
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_interactions import json_values,decode,bits_equal
from experimental.physics_gpu.box_box import float_bits

def main() raises:
    var args=argv();assert_equal(len(args),3);var variant=Int(args[2]);assert_true(variant>=0 and variant<4);var mass=Float64(2);var inertia=Vec3(4.0/3,4.0/3,4.0/3);var half=Vec3(.5,.5,.5)
    if variant==1:mass=.1;inertia=Vec3(.01,.02,.025);half=Vec3(.25,.5,.75)
    if variant==2:mass=100;inertia=Vec3(10,100,100);half=Vec3(.75,.5,.25)
    if variant==3:inertia=Vec3(.2,.3,.4)
    var orders: Array[Int32,4]=[0,5,11,23];var H=Float64(1.0/30);var h=Float64(1.0/120)
    with open(args[1]+"-cases.jsonl","w") as out_file:
        for kind in range(12):
            for oi in range(4):
                var gpu=GpuTemporalFloorFrictionAdvance(point_order=orders[oi]);var floor=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0));var fh=gpu.world.bodies.submit([BodyCommand.create(floor)]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))]);var mu=Float64(.2);var gravity=Vec3(0,-9.81,0);var direction=Vec3(1,0,0);var u=Float64(.3);var accel_t=Float64(0);var drag=mu*9.81;var stop_count=0;var onset_count=0
                if kind==1:direction=Vec3(.6,0,.8);u=.5
                if kind==2:u=drag*h*.25;stop_count=1
                if kind==3:u=drag*h*.5;stop_count=1
                if kind==4:u=drag*h;stop_count=1
                if kind==5:u=drag*h*3.5;stop_count=1
                if kind==6:u=0;accel_t=.8*drag
                if kind==7:u=0;accel_t=1.2*drag;onset_count=1
                if kind==8:u=.02;accel_t=.5*drag;stop_count=1
                if kind==9:u=.04;accel_t=-.5*drag;stop_count=1
                if kind==10:gravity=Vec3(0,0,0);drag=0
                if kind==11:mu=0;drag=0
                var b=RigidBody3D(MassProperties3D(mass,inertia),position=Vec3(0,half.y,0));b.linear_velocity=direction*u;b.force=direction*(mass*accel_t);var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(bh[0],half)])
                var before=gpu.world.bodies.raw();var meta=gpu.world.bodies.metadata();var committed=List[UInt64]()
                with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                    for i in range(16):committed.append(UInt64(ep[i]))
                    for i in range(48):committed.append(float_bits(Float64(la[i])))
                var error=gpu.advance(gravity=gravity,coefficient=mu);var after=gpu.world.bodies.raw();var b_actual=decode(after,Int(bh[0].slot));var report=gpu.report();var stats=List[Float64]();var state=state_words(body_state(b_actual));var values=List[Float64]();var sums=List[Float64]();var pressure=List[Float64]();var diagnostic=List[Float64]()
                for i in range(62):stats.append(report[i])
                for i in range(23):values.append(state[i])
                with gpu._summary.map_to_host() as a:
                    for i in range(6):sums.append(Float64(a[i]))
                with gpu._group.map_to_host() as a:
                    assert_equal(Float64(a[0]),Float64(-987654321.25));assert_equal(Float64(a[13]),Float64(-987654321.25))
                    for i in range(12):pressure.append(Float64(a[1+i]))
                with gpu._candidate.map_to_host() as a:
                    for i in range(len(before)):diagnostic.append(Float64(a[i]))
                var scratch=state_words(body_state(decode(diagnostic,Int(bh[0].slot))));var scratch_values=List[Float64]()
                for i in range(23):scratch_values.append(scratch[i])
                var decel=drag-accel_t;var tstop=Float64(0);var distance=Float64(0);var vfinal=Float64(0)
                if u==0:
                    var acceleration=max(0.0,accel_t-drag);distance=.5*acceleration*H*H;vfinal=acceleration*H
                elif decel>0:
                    tstop=u/decel
                    if tstop<=H:distance=u*u/(2*decel);vfinal=0
                    else:distance=u*H-.5*decel*H*H;vfinal=u-decel*H
                else:distance=u*H-.5*decel*H*H;vfinal=u-decel*H
                var expected_position=Vec3(0,half.y,0)+direction*distance;var expected_velocity=direction*vfinal;var pe=(b_actual.position-expected_position).length();var ve=(b_actual.linear_velocity-expected_velocity).length();var spin=b_actual.angular_velocity.length();var q=b_actual.orientation;var angle=2*sqrt(q.x*q.x+q.y*q.y+q.z*q.z)/abs(q.w);var Jt=Vec3(report[32],0,report[33]);var momentum=(b_actual.linear_velocity-b.linear_velocity)*mass-b.force*H-Vec3(0,mass*gravity.y*H,0)-Vec3(Jt.x,report[5],Jt.z)
                var E0=.5*mass*u*u;var Ef=.5*mass*b_actual.linear_velocity.dot(b_actual.linear_velocity)+.5*(inertia.x*b_actual.angular_velocity.x*b_actual.angular_velocity.x+inertia.y*b_actual.angular_velocity.y*b_actual.angular_velocity.y+inertia.z*b_actual.angular_velocity.z*b_actual.angular_velocity.z);var work_external=mass*accel_t*distance;var dissipation=mass*drag*distance;var energy_error=abs(Ef-E0-work_external+dissipation)
                var valid=error==0 and pe<=1e-10*(1+expected_position.length()) and ve<=1e-10*(1+expected_velocity.length()) and spin<=1e-10 and angle<=1e-10 and momentum.length()<=1e-10*(1+abs(report[5])+Jt.length()) and energy_error<=1e-9*(1+E0+abs(work_external)+dissipation) and report[1]<=1e-5+1e-9 and report[2]<=1e-9*(1+report[17]) and report[30]<=report[41] and report[6]<=1e-9*(1+E0) and Int(report[34])==stop_count and Int(report[35])==onset_count and b_actual.force.length()==0 and b_actual.torque.length()==0
                if stop_count==1:valid=valid and abs(report[36]-tstop)<=1e-10
                out_file.write('{"variant":'+String(variant)+',"kind":'+String(kind)+',"order":'+String(orders[oi])+',"error":'+String(error)+',"mass":'+String(mass)+',"mu":'+String(mu)+',"initial_speed":'+String(u)+',"tangential_acceleration":'+String(accel_t)+',"drag_acceleration":'+String(drag)+',"expected_distance":'+String(distance)+',"expected_final_speed":'+String(vfinal)+',"expected_stop_time":'+String(tstop)+',"expected_stop_count":'+String(stop_count)+',"expected_onset_count":'+String(onset_count)+',"actual":'+json_values(values)+',"candidate":'+json_values(scratch_values)+',"stats":'+json_values(stats)+',"summary":'+json_values(sums)+',"last_group_impulses":'+json_values(pressure)+',"position_error":'+String(pe)+',"velocity_error":'+String(ve)+',"spin":'+String(spin)+',"angle":'+String(angle)+',"momentum_error":'+String(momentum.length())+',"energy_error":'+String(energy_error)+',"physical_pass":'+String(Int(valid))+'}\n')
                if error!=0:
                    bits_equal(before,after)
                    with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                        for i in range(16):assert_equal(UInt64(ep[i]),committed[i])
                        for i in range(48):assert_equal(float_bits(Float64(la[i])),committed[16+i])
                var next=gpu.world.bodies.metadata()
                for i in range(len(meta)):assert_equal(meta[i],next[i])
                gpu.close();assert_true(valid,"STOP: temporal friction first substantive analytic failure; no tuning")
    print("TEMPORAL_FRICTION_ANALYTIC_FIRST_GATE_PASS",variant,48)
