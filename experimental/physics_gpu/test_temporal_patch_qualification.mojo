"""Frozen elementary temporal probes; retain all candidate/rejection diagnostics."""
from std.collections import List,Array
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from std.memory import Pointer
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.temporal_patch_floor import GpuTemporalPatchFloorAdvance
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_interactions import json_values,decode,bits_equal
from experimental.physics_gpu.box_box import float_bits

def probes(prefix: String) raises:
    with open(prefix+"-cases.jsonl","w") as out_file:
        for kind in range(12):
            var gpu=GpuTemporalPatchFloorAdvance();var floor=kind>=2;var e=Float64(0)
            if kind==4:e=.5
            if kind==5:e=1
            var half=Vec3(.5,.5,.5);var mass=Float64(2);var p=Vec3(0,2,0);var v=Vec3(.1,.2,-.1);var omega=Vec3(0,0,0);var force=Vec3(.4,.8,-.2);var torque=Vec3(0,0,0)
            if kind==1:mass=12;half=Vec3(.5,1,1.5);omega=Vec3(.7,1.1,1.5);torque=Vec3(.1,-.2,.15)
            if floor:p=Vec3(0,.5,0);v=Vec3(0,0,0);force=Vec3(0,0,0)
            if kind>=3 and kind<=5:p.y=.502;v.y=-1
            if kind==6:p.y=.49
            if kind==7:omega=Vec3(0,.1,0)
            if kind==8:torque=Vec3(0,0,.1)
            if kind==9:p.x=5
            var floor_body=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0))
            if floor:
                var fh=gpu.world.bodies.submit([BodyCommand.create(floor_body)]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))])
            var b=RigidBody3D(MassProperties3D.box(mass,half*2),position=p);b.linear_velocity=v;b.angular_velocity=omega;b.force=force;b.torque=torque
            var handle=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(handle[0],half)])
            if kind==10:
                var more=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(more[0],half)])
            var before=gpu.world.bodies.raw();var meta=gpu.world.bodies.metadata();var committed=List[UInt64]()
            with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                for i in range(16):committed.append(UInt64(ep[i]))
                for i in range(48):committed.append(float_bits(Float64(la[i])))
            var dt=Float64(1.0/60 if kind==11 else 1.0/30)
            var error=gpu.advance(dt,restitution=e);var after=gpu.world.bodies.raw();var diagnostic=List[Float64]()
            with gpu._candidate.map_to_host() as ca:
                for i in range(len(before)):diagnostic.append(Float64(ca[i]))
            var report=gpu.report();var stats=List[Float64]();var lambda_n=List[Float64]()
            for i in range(30):stats.append(report[i])
            with gpu._group.map_to_host() as a:
                assert_equal(Float64(a[0]),Float64(-987654321.25));assert_equal(Float64(a[5]),Float64(-987654321.25))
                for i in range(4):lambda_n.append(Float64(a[1+i]))
            var slot=Int(handle[0].slot);var initial=state_words(body_state(decode(before,slot)));var candidate=state_words(body_state(decode(diagnostic,slot)));var init_values=List[Float64]();var candidate_values=List[Float64]()
            for i in range(23):init_values.append(initial[i]);candidate_values.append(candidate[i])
            var sum_values=List[Float64]()
            with gpu._summary.map_to_host() as a:
                for i in range(6):sum_values.append(Float64(a[i]))
            out_file.write('{"kind":'+String(kind)+',"error":'+String(error)+',"floor":'+String(Int(floor))+',"e":'+String(e)+',"dt":'+String(dt)+',"half":'+json_values([half.x,half.y,half.z])+',"entry":'+json_values(init_values)+',"candidate":'+json_values(candidate_values)+',"summary":'+json_values(sum_values)+',"stats":'+json_values(stats)+',"last_group_pressure":'+json_values(lambda_n)+'}\n')
            assert_true((error==0)==(kind<6),"STOP: narrow physical acceptance failed")
            if error!=0:
                bits_equal(before,after)
                with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                    for i in range(16):assert_equal(UInt64(ep[i]),committed[i])
                    for i in range(48):assert_equal(float_bits(Float64(la[i])),committed[16+i])
            else:
                assert_equal(after[17*258+slot+1],Float64(0));assert_equal(after[20*258+slot+1],Float64(0))
                assert_true(kind<6)
            var next=gpu.world.bodies.metadata()
            for i in range(len(meta)):assert_equal(meta[i],next[i])
            print("TEMPORAL_FLOOR_PROBE",kind,"error",error,"normal_residual",report[2],"max_spin",report[3],"orientation_error",report[4],"penetration",report[1],"events",sum_values[2])
            gpu.close()
    print("TEMPORAL_FLOOR_FROZEN_PROBES_AND_REJECTION_ROLLBACK_RECORDED")

from experimental.physics_gpu.temporal_patch_floor_kernels import correct,corner
from experimental.physics_gpu.kernels import load,store
from experimental.physics_gpu.box_response_reference import reference_block
from experimental.physics_gpu.response_kernels import inv_inertia,kinetic

def group_probe(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],group: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],mode: Int32,order: Int32):
    var b=load(current,0);var pressure=Array[Float64,4](fill=.25 if mode==1 else 0.0)
    for i in range(6):summary[unsafe_offset=i]=0
    for i in range(1,31):stats[unsafe_offset=i]=0
    correct(b,Vec3(.5,.5,.5),0,pressure,0,2,summary,stats,order)
    store(candidate,0,b)
    for i in range(4):group[unsafe_offset=1+i]=pressure[i]

def units(prefix: String) raises:
    with open(prefix+"-units.jsonl","w") as out_file:
        for mode in range(4):
            for order in range(24):
                var gpu=GpuTemporalPatchFloorAdvance();var b=RigidBody3D(MassProperties3D(2,Vec3(.2,.3,.4)),position=Vec3(0,.5,0));b.linear_velocity.y=-.01;b.angular_velocity=Vec3(.1,0,-.08)
                if mode==1:b.linear_velocity.y=.5;b.angular_velocity=Vec3(0,0,0)
                if mode==2:b.position.y+=.0001
                if mode==3:b.orientation=Quaternion.axis_angle(Vec3(1,0,0),.001)
                _=gpu.world.bodies.submit([BodyCommand.create(b)]);var before=gpu.world.bodies.raw()
                gpu.world.bodies._ctx.enqueue_function[group_probe](gpu.world.bodies._current,gpu._candidate,gpu._group,gpu._summary,gpu._stats,Int32(mode),Int32(order),grid_dim=1,block_dim=1);gpu.world.bodies._ctx.synchronize()
                var code=Int32(0);var pressure=Array[Float64,4](fill=0);var after=List[Float64]()
                with gpu._summary.map_to_host() as a:code=Int32(a[0])
                with gpu._group.map_to_host() as a:
                    for i in range(4):pressure[i]=Float64(a[1+i])
                with gpu._candidate.map_to_host() as a:
                    for i in range(len(before)):after.append(Float64(a[i]))
                var actual=decode(after,0);var expected=b;var lambda_cpu=Array[Float64,4](fill=.25 if mode==1 else 0.0)
                if mode<2:
                    var gram=Array[Float64,16](fill=0);var q=Array[Float64,4](fill=0);var arms=Array[Vec3,4](fill=Vec3(0,0,0));var bs=body_state(b)
                    for i in range(4):arms[i]=Vec3(.5 if i%2==0 else -.5,0,-.5 if i<2 else .5)
                    for i in range(4):
                        q[i]=b.linear_velocity.y+arms[i].x*b.angular_velocity.x+arms[i].z*b.angular_velocity.z
                        for j in range(4):gram[i*4+j]=.5+arms[i].x*arms[j].x/.2+arms[i].z*arms[j].z/.4;q[i]-=gram[i*4+j]*lambda_cpu[j]
                    var result=reference_block(gram,q,4);var total=Float64(0);var torque=Vec3(0,0,0)
                    for i in range(4):var delta=result[i]-lambda_cpu[i];total+=delta;torque=torque+arms[i]*delta;lambda_cpu[i]=result[i]
                    expected.linear_velocity.y+=total/2;expected.angular_velocity=expected.angular_velocity+Vec3(torque.x/.2,torque.y/.3,torque.z/.4)
                var valid=code==0 if mode<2 else code==310;var av=state_words(body_state(actual));var ev=state_words(body_state(expected));var ratio=Float64(0)
                for i in range(23):ratio=max(ratio,abs(av[i]-ev[i])/(1e-10*(1+abs(ev[i]))))
                for i in range(4):ratio=max(ratio,abs(pressure[i]-lambda_cpu[i])/(1e-10*(1+abs(lambda_cpu[i]))))
                valid=valid and ratio<=1
                out_file.write('{"mode":'+String(mode)+',"order":'+String(order)+',"code":'+String(code)+',"CPU_state_pressure_tolerance_ratio":'+String(ratio)+',"pressure":'+json_values([pressure[0],pressure[1],pressure[2],pressure[3]])+',"physical_pass":'+String(Int(valid))+'}\n')
                gpu.close();assert_true(valid,"STOP: patch independent unit gate failed")
    print("PATCH_INDEPENDENT_GROUP_CPU_AND_INVALID_FACE_PASS",96)

def trajectories(prefix: String) raises:
    with open(prefix+"-trajectory.jsonl","w") as out_file:
        for kind in range(7):
            var floor=kind>=2;var gpu=GpuTemporalPatchFloorAdvance();var e=Float64(0)
            if kind==4:e=.5
            if kind==5:e=1
            var p=Vec3(0,2,0);var v=Vec3(.1,.2,-.1);var half=Vec3(.5,.5,.5);var force=Vec3(.4,.8,-.2);var torque=Vec3(0,0,0);var mass=Float64(2)
            if floor:p=Vec3(0,.5,0);v=Vec3(0,0,0);force=Vec3(0,0,0)
            if kind>=3 and kind<=5:p.y=.502;v.y=-1
            if kind==6:force=Vec3(0,-4,0)
            if kind==1:mass=12;half=Vec3(.5,1,1.5);torque=Vec3(.1,-.2,.15)
            if floor:
                var fh=gpu.world.bodies.submit([BodyCommand.create(RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0)))]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))])
            var b=RigidBody3D(MassProperties3D.box(mass,half*2),position=p);b.linear_velocity=v
            if kind==1:b.angular_velocity=Vec3(.7,1.1,1.5)
            var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(bh[0],half)])
            var expected_y=p.y;var expected_v=v.y;var expected_events=0;var total_events=0;var a=-9.81+force.y/mass;var H=Float64(1.0/30)
            for frame in range(30):
                _=gpu.world.bodies.submit([BodyCommand.force(bh[0],force,torque)]);var before=gpu.world.bodies.raw();var entry=state_words(body_state(decode(before,Int(bh[0].slot))));var error=gpu.advance(restitution=e);var after=gpu.world.bodies.raw();var actual=decode(after,Int(bh[0].slot));var av=state_words(body_state(actual));var report=gpu.report();var su=List[Float64]();var states=List[Float64]();var ent=List[Float64]();var stats=List[Float64]()
                for i in range(23):states.append(av[i]);ent.append(entry[i])
                for i in range(30):stats.append(report[i])
                with gpu._summary.map_to_host() as d:
                    for i in range(6):su.append(Float64(d[i]))
                total_events+=Int(su[2]);var remaining=H
                if floor:
                    for event in range(6):
                        if remaining<=0:break
                        if expected_y<=.5+1e-14 and abs(expected_v)<=1e-14:expected_y=.5;expected_v=0;remaining=0;break
                        var gap=max(0.0,expected_y-.5);var root=(-expected_v-sqrt(expected_v*expected_v-2*a*gap))/a
                        if root<0 or root>remaining:expected_y+=expected_v*remaining+.5*a*remaining*remaining;expected_v+=a*remaining;remaining=0;break
                        expected_y=.5;expected_v+=a*root;remaining-=root;expected_v=-e*expected_v if expected_v<-.2 else 0.0;expected_events+=1
                else:expected_y+=expected_v*H+.5*a*H*H;expected_v+=a*H
                var pe=abs(actual.position.y-expected_y);var ve=abs(actual.linear_velocity.y-expected_v);var valid=error==0 and pe<=1e-10*(1+abs(expected_y)) and ve<=1e-10*(1+abs(expected_v))
                if floor:
                    valid=valid and actual.angular_velocity.length()<=1e-10 and abs(actual.orientation.x)+abs(actual.orientation.y)+abs(actual.orientation.z)<=1e-10 and total_events==expected_events and report[1]<=1e-5+1e-9 and report[6]<=1e-9*(1+.5*mass*entry[12]*entry[12])
                out_file.write('{"kind":'+String(kind)+',"frame":'+String(frame)+',"error":'+String(error)+',"e":'+String(e)+',"floor":'+String(Int(floor))+',"half":'+json_values([half.x,half.y,half.z])+',"entry":'+json_values(ent)+',"actual":'+json_values(states)+',"stats":'+json_values(stats)+',"summary":'+json_values(su)+',"position_error_m":'+String(pe)+',"velocity_error_mps":'+String(ve)+',"events_total":'+String(total_events)+',"analytic_events_total":'+String(expected_events)+',"physical_pass":'+String(Int(valid))+'}\n')
                if error!=0:bits_equal(before,after)
                if not valid:gpu.close();assert_true(False,"STOP: consecutive temporal physical gate failed; no tuning")
            gpu.close()
    print("TEMPORAL_PATCH_GENUINE_ONE_SECOND_TRAJECTORIES_PASS",210)

def main() raises:
    var args=argv();assert_equal(len(args),2);units(args[1]);probes(args[1]);trajectories(args[1])
