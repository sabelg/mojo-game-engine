"""Frozen elementary temporal probes; retain all candidate/rejection diagnostics."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.temporal_floor import GpuTemporalFloorAdvance
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_interactions import json_values,decode,bits_equal
from experimental.physics_gpu.box_box import float_bits

def main() raises:
    var args=argv();assert_equal(len(args),2);var prefix=args[1]
    with open(prefix+"-cases.jsonl","w") as out_file:
        for kind in range(12):
            var gpu=GpuTemporalFloorAdvance();var floor=kind>=2;var e=Float64(0)
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
