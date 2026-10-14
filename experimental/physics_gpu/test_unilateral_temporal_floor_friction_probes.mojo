"""Independent impacts, pressure/unsupported domains and transactional caps."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.unilateral_temporal_floor_friction import GpuUnilateralTemporalFloorFrictionAdvance
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_interactions import json_values,decode,bits_equal
from experimental.physics_gpu.box_box import float_bits

def main() raises:
    var args=argv();assert_equal(len(args),3);var variant=Int(args[2]);var mass=Float64(2);var I=Vec3(4.0/3,4.0/3,4.0/3);var half=Vec3(.5,.5,.5)
    if variant==1:mass=.1;I=Vec3(.01,.02,.025);half=Vec3(.25,.5,.75)
    if variant==2:mass=100;I=Vec3(10,100,100);half=Vec3(.75,.5,.25)
    if variant==3:I=Vec3(.2,.3,.4)
    var H=Float64(1.0/30);var h=Float64(1.0/120);var direction=Vec3(.6,0,.8)
    with open(args[1]+"-cases.jsonl","w") as out_file:
        for kind in range(15):
            for oi in range(2):
                var order=Int32(0 if oi==0 else 11);var gpu=GpuUnilateralTemporalFloorFrictionAdvance(point_order=order,stop_budget=Int32(0 if kind==11 else 4),segment_budget=Int32(0 if kind==13 else 6));var fh=gpu.world.bodies.submit([BodyCommand.create(RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0)))]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))]);var g=Float64(9.81);var mu=Float64(.2);var e=Float64(0)
                if kind==1 or kind==4:e=.5
                if kind==2:e=1
                if kind==3 or kind==10:g=0
                if kind==4 or kind==14:mu=0
                if kind==14:g=10000;e=.5
                var b=RigidBody3D(MassProperties3D(mass,I),position=Vec3(0,half.y+.002,0));b.linear_velocity=direction*.5+Vec3(0,-1,0)
                if kind>=5 and kind<=13:b.position.y=half.y;b.linear_velocity=direction*.5
                if kind==5:b.force=Vec3(mass,0,0)
                if kind==6:b.torque=Vec3(0,0,.1)
                if kind==7:b.orientation=Quaternion.axis_angle(Vec3(1,0,0),.001)
                if kind==8 or kind==9:mu=half.x/half.y*(1.1 if kind==8 else 1.0);b.linear_velocity=Vec3(1,0,0)
                if kind==11:b.linear_velocity=Vec3(.75*.2*9.81*h*.5,0,0);b.force=Vec3(.25*.2*9.81*mass,0,0)
                if kind==12:b.linear_velocity=Vec3(3*.2*9.81*2.5*h,0,0);b.force=Vec3(-2*.2*9.81*mass,0,0)
                var initial=b
                if kind==11 or kind==12:b.linear_velocity=Vec3(0,0,0);b.force=Vec3(0,0,0)
                var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(bh[0],half)])
                if kind==11 or kind==12:
                    assert_equal(gpu.advance(coefficient=mu),Int32(0));_=gpu.world.bodies.submit([BodyCommand.update(bh[0],initial)])
                var before=gpu.world.bodies.raw();var meta=gpu.world.bodies.metadata();var committed=List[UInt64]()
                with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                    for i in range(16):committed.append(UInt64(ep[i]))
                    for i in range(48):committed.append(float_bits(Float64(la[i])))
                var code=gpu.advance(gravity=Vec3(0,-g,0),coefficient=mu,restitution=e);var after=gpu.world.bodies.raw();var actual=decode(after,Int(bh[0].slot));var report=gpu.report();var vals=List[Float64]();var av=state_words(body_state(actual));var stats=List[Float64]();var summary=List[Float64]();var candidate=List[Float64]();var input=List[Float64]();var output=List[Float64]()
                for i in range(23):vals.append(av[i])
                for i in range(62):stats.append(report[i])
                with gpu._summary.map_to_host() as a:
                    for i in range(6):summary.append(Float64(a[i]))
                with gpu._candidate.map_to_host() as a:
                    var raw=List[Float64]()
                    for i in range(len(before)):raw.append(Float64(a[i]))
                    var state=state_words(body_state(decode(raw,Int(bh[0].slot))))
                    for i in range(23):candidate.append(state[i])
                with gpu._block_input.map_to_host() as a,gpu._block_output.map_to_host() as o:
                    assert_equal(Float64(a[0]),Float64(-987654321.25));assert_equal(Float64(a[63]),Float64(-987654321.25));assert_equal(Float64(o[0]),Float64(-987654321.25));assert_equal(Float64(o[63]),Float64(-987654321.25))
                    for i in range(64):input.append(Float64(a[i]));output.append(Float64(o[i]))
                var expected_code=Int32(0)
                if kind==5:expected_code=511
                if kind==6 or kind==7:expected_code=301
                if kind==8 or kind==9:expected_code=1305
                if kind==11:expected_code=513
                if kind==12:expected_code=512
                if kind==13:expected_code=517
                if kind==14:expected_code=305
                var valid=code==expected_code;var pe=Float64(0);var ve=Float64(0);var momentum=Float64(0);var energy_error=Float64(0);var expected_distance=Float64(0);var expected_tangent_speed=Float64(0);var expected_y=Float64(0);var expected_vy=Float64(0)
                if code!=0:
                    bits_equal(before,after)
                    with gpu._episode.map_to_host() as ep,gpu._last.map_to_host() as la:
                        for i in range(16):assert_equal(UInt64(ep[i]),committed[i])
                        for i in range(48):assert_equal(float_bits(Float64(la[i])),committed[16+i])
                    if kind==11 or kind==12 or kind==14:valid=valid and report[0]>0
                elif code==0:
                    var t=Float64(.002);var V=Float64(1)
                    if g>0:V=sqrt(1+2*g*.002);t=(V-1)/g
                    var remain=H-t;var beta=e*V;var post=max(0.0,.5-mu*(1+e)*V);expected_tangent_speed=post;expected_distance=.5*t+post*remain;expected_y=half.y+beta*remain-.5*g*remain*remain;expected_vy=beta-g*remain
                    var normal_loss=.5*mass*(1-e*e)*V*V;var impact_tangent_loss=.5*mass*(.25-post*post);var support_loss=Float64(0)
                    if e==0:expected_y=half.y;expected_vy=0
                    if e==0 and g>0:
                        expected_tangent_speed=max(0.0,post-mu*g*remain);expected_distance=.5*t+post*remain-.5*mu*g*remain*remain;support_loss=mu*mass*g*(expected_distance-.5*t)
                    if kind==10:expected_y=half.y;expected_vy=0;expected_tangent_speed=.5;expected_distance=.5*H;normal_loss=0;impact_tangent_loss=0;support_loss=0
                    var p=Vec3(0,expected_y,0)+direction*expected_distance;var v=direction*expected_tangent_speed+Vec3(0,expected_vy,0);pe=(actual.position-p).length();ve=(actual.linear_velocity-v).length()
                    var entry=decode(before,Int(bh[0].slot));var J=Vec3(report[32],report[5],report[33]);momentum=((actual.linear_velocity-entry.linear_velocity)*mass-entry.force*H-Vec3(0,-mass*g*H,0)-J).length()
                    var energy0=.5*mass*entry.linear_velocity.dot(entry.linear_velocity)+mass*g*entry.position.y;var energy1=.5*mass*actual.linear_velocity.dot(actual.linear_velocity)+mass*g*actual.position.y;energy_error=abs(energy1-energy0+normal_loss+impact_tangent_loss+support_loss)
                    valid=valid and pe<=1e-10*(1+p.length()) and ve<=1e-10*(1+v.length()) and actual.angular_velocity.length()<=1e-10 and abs(actual.orientation.x)+abs(actual.orientation.y)+abs(actual.orientation.z)<=1e-10 and momentum<=1e-10*(1+J.length()) and energy_error<=1e-9*(1+abs(energy0)) and actual.force.length()==0 and actual.torque.length()==0 and summary[2]==Float64(0 if kind==10 else 1)
                    if kind==3 or kind==10:valid=valid and abs(report[5]-mass*(1.0 if kind==3 else 0.0))<=1e-10 and report[39]==0 and report[40]==0
                var next=gpu.world.bodies.metadata()
                for i in range(len(meta)):assert_equal(meta[i],next[i])
                out_file.write('{"variant":'+String(variant)+',"kind":'+String(kind)+',"order":'+String(order)+',"expected_code":'+String(expected_code)+',"code":'+String(code)+',"gravity":'+String(g)+',"mu":'+String(mu)+',"e":'+String(e)+',"mass":'+String(mass)+',"actual":'+json_values(vals)+',"candidate":'+json_values(candidate)+',"stats":'+json_values(stats)+',"summary":'+json_values(summary)+',"block_input":'+json_values(input)+',"block_output":'+json_values(output)+',"expected_distance":'+String(expected_distance)+',"expected_speed":'+String(expected_tangent_speed)+',"expected_y":'+String(expected_y)+',"expected_vy":'+String(expected_vy)+',"position_error":'+String(pe)+',"velocity_error":'+String(ve)+',"momentum_error":'+String(momentum)+',"energy_error":'+String(energy_error)+',"physical_pass":'+String(Int(valid))+'}\n');gpu.close();assert_true(valid,"STOP: first substantive temporal impact/protocol physical failure; no tuning")
    print("TEMPORAL_FRICTION_IMPACT_PROTOCOL_PASS",variant,30)
