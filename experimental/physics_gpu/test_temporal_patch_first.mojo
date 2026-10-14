"""First two causal failures, valid mass/inertia variants and all point orders."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,RigidBody3D,MassProperties3D
from experimental.physics_gpu.temporal_patch_floor import GpuTemporalPatchFloorAdvance
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_interactions import json_values,decode,bits_equal
from experimental.physics_gpu.box_box import float_bits

def main() raises:
    var args=argv();assert_equal(len(args),3);var prefix=args[1];var variant=Int(args[2]);assert_true(variant>=0 and variant<4)
    var mass=Float64(2);var inertia=Vec3(4.0/3,4.0/3,4.0/3);var half=Vec3(.5,.5,.5)
    if variant==1:mass=.1;inertia=Vec3(.01,.02,.025);half=Vec3(.25,.5,.75)
    if variant==2:mass=100;inertia=Vec3(10,100,100);half=Vec3(.75,.5,.25)
    if variant==3:inertia=Vec3(.2,.3,.4)
    with open(prefix+"-cases.jsonl","w") as out_file:
        for kind in range(2):
            for order in range(24):
                var gpu=GpuTemporalPatchFloorAdvance(point_order=Int32(order));var floor=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0));var fh=gpu.world.bodies.submit([BodyCommand.create(floor)]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))])
                var b=RigidBody3D(MassProperties3D(mass,inertia),position=Vec3(0,.5 if kind==0 else .502,0));b.linear_velocity=Vec3(0,0.0 if kind==0 else -1.0,0)
                var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(bh[0],half)])
                var before=gpu.world.bodies.raw();var metadata=gpu.world.bodies.metadata();var error=gpu.advance(restitution=Float64(0.0 if kind==0 else 1.0));var after=gpu.world.bodies.raw();var report=gpu.report();var sv=List[Float64]();var lv=List[Float64]();var su=List[Float64]()
                for i in range(30):sv.append(report[i])
                with gpu._group.map_to_host() as a:
                    assert_equal(Float64(a[0]),Float64(-987654321.25));assert_equal(Float64(a[5]),Float64(-987654321.25))
                    for i in range(4):lv.append(Float64(a[1+i]))
                with gpu._summary.map_to_host() as a:
                    for i in range(6):su.append(Float64(a[i]))
                var actual=decode(after,Int(bh[0].slot));var state=state_words(body_state(actual));var values=List[Float64]()
                for i in range(23):values.append(state[i])
                var H=Float64(1.0/30);var V=sqrt(1+2*9.81*.002);var toi=(V-1)/9.81;var rest=H-toi
                var y=Float64(.5) if kind==0 else .5+V*rest-.5*9.81*rest*rest;var v=Float64(0.0) if kind==0 else V-9.81*rest
                var position_error=abs(actual.position.y-y);var velocity_error=abs(actual.linear_velocity.y-v);var spin=actual.angular_velocity.length();var q=actual.orientation;var angle=2*sqrt(q.x*q.x+q.y*q.y+q.z*q.z)/abs(q.w)
                var balance=mass*(actual.linear_velocity.y-b.linear_velocity.y)+mass*9.81*H-report[5]
                var valid=error==0 and position_error<=1e-10*(1+abs(y)) and velocity_error<=1e-10*(1+abs(v)) and spin<=1e-10 and angle<=1e-10 and abs(balance)<=1e-10*(1+abs(report[5])) and report[1]<=1e-5+1e-9 and report[6]<=1e-9*(1+.5*mass*V*V)
                if kind==0:valid=valid and report[2]<=1e-9*(1+report[17])
                else:valid=valid and abs(report[8]+V)<=1e-10*(1+V) and abs(report[9]-V)<=1e-10*(1+V) and abs(report[10]-toi)<=1e-10 and report[11]<=1e-9
                out_file.write('{"variant":'+String(variant)+',"kind":'+String(kind)+',"order":'+String(order)+',"error":'+String(error)+',"mass":'+String(mass)+',"inertia":'+json_values([inertia.x,inertia.y,inertia.z])+',"half":'+json_values([half.x,half.y,half.z])+',"actual":'+json_values(values)+',"stats":'+json_values(sv)+',"pressure":'+json_values(lv)+',"summary":'+json_values(su)+',"position_error_m":'+String(position_error)+',"velocity_error_mps":'+String(velocity_error)+',"spin_error_radps":'+String(spin)+',"angle_error_rad":'+String(angle)+',"momentum_balance_error":'+String(balance)+',"physical_pass":'+String(Int(valid))+'}\n')
                var next=gpu.world.bodies.metadata()
                for i in range(len(metadata)):assert_equal(metadata[i],next[i])
                gpu.close();assert_true(valid,"STOP: corrected patch first physical gate failed; no tuning")
        print("TEMPORAL_PATCH_FIRST_PHYSICAL_PERMUTATIONS_PASS",variant,48)
