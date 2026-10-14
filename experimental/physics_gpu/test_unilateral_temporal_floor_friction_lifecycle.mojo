"""Committed-episode rollback, force consumption and prior registry boundaries."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,RigidBody3D,MassProperties3D
from experimental.physics_gpu.unilateral_temporal_floor_friction import GpuUnilateralTemporalFloorFrictionAdvance
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.box_box import float_bits
from experimental.physics_gpu.test_box_interactions import bits_equal,decode

def main() raises:
    var args=argv();assert_equal(len(args),2)
    with open(args[1]+"-lifecycle.jsonl","w") as out_file:
        for kind in range(15):
            var gpu=GpuUnilateralTemporalFloorFrictionAdvance(point_order=Int32(0 if kind%2==0 else 11));var fh=gpu.world.bodies.submit([BodyCommand.create(RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0)))]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))]);var b=RigidBody3D(MassProperties3D.box(2,Vec3(1,1,1)),position=Vec3(0,.5,0));var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);var shapes=gpu.world.submit_boxes([BoxCommand.attach(bh[0],Vec3(.5,.5,.5))]);assert_equal(gpu.advance(),Int32(0))
            _=gpu.world.bodies.submit([BodyCommand.force(bh[0],Vec3(0,-4,0))]);var dt=Float64(1.0/30);var e=Float64(0);var mu=Float64(0)
            if kind==0:dt=1.0/60
            if kind==1:e=1.1
            if kind==2:mu=-.1
            if kind==3:_=gpu.world.bodies.submit([BodyCommand.force(fh[0],Vec3(0,1,0))])
            if kind==4:b.position.y=.6;_=gpu.world.bodies.submit([BodyCommand.update(bh[0],b)])
            if kind==5:b.position.y=.502;b.linear_velocity.y=-1;_=gpu.world.bodies.submit([BodyCommand.update(bh[0],b)]);e=1
            if kind==6:
                _=gpu.world.bodies.submit([BodyCommand.remove(bh[0])]);var replacement=gpu.world.bodies.submit([BodyCommand.create(b)]);assert_equal(replacement[0].slot,bh[0].slot);assert_true(replacement[0].generation!=bh[0].generation);bh=replacement^;_=gpu.world.submit_boxes([BoxCommand.attach(bh[0],Vec3(.5,.5,.5))])
            if kind==7:
                var old_shape=shapes[0];_=gpu.world.submit_boxes([BoxCommand.detach(old_shape)]);var replacement=gpu.world.submit_boxes([BoxCommand.attach(bh[0],Vec3(.5,.5,.5))]);assert_equal(replacement[0].slot,old_shape.slot);assert_equal(replacement[0].generation,old_shape.generation+1);assert_equal(replacement[0].owner,old_shape.owner);shapes=replacement^;e=1
            if kind==8:e=1
            if kind==9:_=gpu.world.submit_boxes([BoxCommand.reshape(shapes[0],Vec3(.5,.5,.5))]);mu=.3;e=1
            if kind==10:mu=.4;e=1
            if kind==11:b.torque=Vec3(0,0,.1);_=gpu.world.bodies.submit([BodyCommand.update(bh[0],b)])
            if kind==12:b.linear_velocity=Vec3(.3,0,.4);b.force=Vec3(2,0,0);_=gpu.world.bodies.submit([BodyCommand.update(bh[0],b)]);mu=.2
            if kind==13:b.force=Vec3(0,40,0);_=gpu.world.bodies.submit([BodyCommand.update(bh[0],b)])
            if kind==14:_=gpu.world.submit_boxes([BoxCommand.reshape(shapes[0],Vec3(.5,.5,.5),center=Vec3(.001,0,0))])
            var before=gpu.world.bodies.raw();var meta=gpu.world.bodies.metadata();var committed=List[UInt64]()
            with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                for i in range(16):committed.append(UInt64(ep[i]))
                for i in range(48):committed.append(float_bits(Float64(la[i])))
            var error=gpu.advance(dt,restitution=e,coefficient=mu);var after=gpu.world.bodies.raw();var report=gpu.report();var toi_admissions=Int32(0)
            # Counts admitted TOI roots, including t=0 cold discovery; not bounce impulses.
            # Identity replacement loses touching eligibility; derive cold t=0
            # admission from saved physical entry direction, independent of bounce.
            with gpu._summary.map_to_host() as a:toi_admissions=Int32(a[2])
            var expected_rejection=kind<4 or kind>=11;var valid=(error!=0) if expected_rejection else error==0
            if error!=0:
                bits_equal(before,after)
                with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                    for i in range(16):assert_equal(UInt64(ep[i]),committed[i])
                    for i in range(48):assert_equal(float_bits(Float64(la[i])),committed[16+i])
            if not expected_rejection:
                var actual=decode(after,Int(bh[0].slot));var y=Float64(.5);var v=Float64(0)
                if kind==4:y=.6-.5*9.81/900;v=-9.81/30
                if kind==5:
                    var V=sqrt(1+2*9.81*.002);var toi=(V-1)/9.81;var h=1.0/30-toi;y=.5+V*h-.5*9.81*h*h;v=V-9.81*h
                valid=valid and abs(actual.position.y-y)<=1e-10*(1+abs(y)) and abs(actual.linear_velocity.y-v)<=1e-10*(1+abs(v)) and actual.angular_velocity.length()<=1e-10 and actual.force.length()==0 and actual.torque.length()==0 
                with gpu._episode.map_to_host() as ep:
                    valid=valid and UInt64(ep[1])==1 and UInt64(ep[2])==UInt64(0 if kind==4 or kind==5 else 1)
                var entry=decode(before,Int(bh[0].slot));var expected_roots=1 if kind==5 or ((kind==7 or kind==9) and entry.linear_velocity.y<0) else 0
                valid=valid and toi_admissions==Int32(expected_roots)
                if kind==6 or kind==7 or kind==9:
                    var changed=False
                    with gpu._episode.map_to_host() as ep:
                        for i in range(3,14):changed=changed or UInt64(ep[i])!=committed[i]
                    valid=valid and changed
            if kind==7 or kind==9 or kind==10:
                # A generation/revision/material change must add no restitution kick.
                assert_equal(report[9],Float64(0));assert_true(report[6]<=1e-9);assert_equal(report[10],Float64(0))
                with gpu._episode.map_to_host() as ep:
                    assert_equal(UInt64(ep[8]),UInt64(shapes[0].slot));assert_equal(UInt64(ep[9]),shapes[0].generation);assert_equal(UInt64(ep[11]),UInt64(bh[0].slot));assert_equal(UInt64(ep[12]),bh[0].generation);assert_equal(UInt64(ep[13]),bh[0].owner)
                    if kind==7:assert_true(UInt64(ep[9])!=committed[9])
                    if kind==9:assert_true(UInt64(ep[10])!=committed[10])
            var next=gpu.world.bodies.metadata()
            for i in range(len(meta)):assert_equal(next[i],meta[i])
            out_file.write('{"kind":'+String(kind)+',"error":'+String(error)+',"events":'+String(toi_admissions)+',"physical_pass":'+String(Int(valid))+'}\n');gpu.close();assert_true(valid,"STOP: committed episode lifecycle physical gate failed")
    print("UNILATERAL_FRICTION_COMMITTED_EPISODE_LIFECYCLE_PASS",15)
