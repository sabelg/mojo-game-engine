"""Targeted saved failure and independent separating/approaching boundaries."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from mojo_game import Vec3,RigidBody3D,MassProperties3D
from experimental.physics_gpu.unilateral_temporal_floor_friction import GpuUnilateralTemporalFloorFrictionAdvance
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_interactions import decode,json_values,bits_equal
from experimental.physics_gpu.box_box import float_bits

def main() raises:
    var args=argv();assert_equal(len(args),3);var variant=Int(args[2]);var m=Float64(2);var I=Vec3(4.0/3,4.0/3,4.0/3);var half=Vec3(.5,.5,.5)
    if variant==1:m=.1;I=Vec3(.01,.02,.025);half=Vec3(.25,.5,.75)
    if variant==2:m=100;I=Vec3(10,100,100);half=Vec3(.75,.5,.25)
    if variant==3:I=Vec3(.2,.3,.4)
    var H=Float64(1.0/30)
    with open(args[1]+"-cases.jsonl","w") as file:
        for kind in range(12):
            for oi in range(2):
                var order=Int32(0 if oi==0 else 11);var gpu=GpuUnilateralTemporalFloorFrictionAdvance(point_order=order);var fh=gpu.world.bodies.submit([BodyCommand.create(RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0)))]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))]);var gap=Float64(0);var vy=Float64(0);var g=Float64(0);var vx=Float64(.3);var vz=Float64(0);var tiny=Float64(5.551115123125783e-17)
                if kind==0:gap=.002;vy=-1;vz=.4
                if kind==1:vy=tiny
                if kind==2:vy=-tiny
                if kind==3:vy=1e-12
                if kind==4:vy=-1e-12
                if kind==5:vy=.1
                if kind==6:gap=.002;vy=.1
                if kind==7:gap=.002;vy=-.1
                if kind==8:vy=tiny;g=9.81
                if kind==9:vy=-tiny;g=9.81
                if kind==10:vy=.1;g=9.81
                if kind==11:vy=.5;g=9.81
                var b=RigidBody3D(MassProperties3D(m,I),position=Vec3(0,half.y+gap,0));b.linear_velocity=Vec3(vx,vy,vz);var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);_=gpu.world.submit_boxes([BoxCommand.attach(bh[0],half)]);var before=gpu.world.bodies.raw();var meta=gpu.world.bodies.metadata();var ep0=List[UInt64]()
                with gpu._episode.map_to_host() as e,gpu._last.map_to_host() as l:
                    for i in range(16):ep0.append(UInt64(e[i]))
                    for i in range(48):ep0.append(float_bits(Float64(l[i])))
                var error=gpu.advance(gravity=Vec3(0,-g,0),coefficient=.2);var after=gpu.world.bodies.raw();var actual=decode(after,Int(bh[0].slot));var r=gpu.report();var av=state_words(body_state(actual));var values=List[Float64]();var stats=List[Float64]();var summary=List[Float64]()
                for i in range(23):values.append(av[i])
                for i in range(62):stats.append(r[i])
                with gpu._summary.map_to_host() as a:
                    for i in range(6):summary.append(Float64(a[i]))
                var t=Float64(0);var hit=False;var V=Float64(0);var incoming_speed=sqrt(vx*vx+vz*vz);var distance=incoming_speed*H;var speed=incoming_speed;var y=half.y+gap+vy*H-.5*g*H*H;var vn=vy-g*H;var normal_loss=Float64(0);var impact_loss=Float64(0);var support_loss=Float64(0)
                if g==0:
                    if vy<0:t=gap/(-vy);hit=t<=H;V=-vy
                else:
                    V=sqrt(vy*vy+2*g*gap);t=(vy+V)/g;hit=t<=H
                if hit:
                    var rem=H-t;var post=max(0.0,incoming_speed-.2*V);var drag=.2*g;distance=incoming_speed*t
                    if drag>0:
                        var stop=post/drag;var duration=min(rem,stop);distance+=post*duration-.5*drag*duration*duration;speed=max(0.0,post-drag*rem);support_loss=.2*m*g*(distance-incoming_speed*t)
                    else:distance+=post*rem;speed=post
                    y=half.y;vn=0;normal_loss=.5*m*V*V;impact_loss=.5*m*(incoming_speed*incoming_speed-post*post)
                var d=Vec3(vx,0,vz)*(1/incoming_speed);var expected_p=d*distance+Vec3(0,y,0);var expected_v=d*speed+Vec3(0,vn,0);var pe=(actual.position-expected_p).length();var ve=(actual.linear_velocity-expected_v).length();var J=Vec3(r[32],r[5],r[33]);var momentum=((actual.linear_velocity-b.linear_velocity)*m-Vec3(0,-m*g*H,0)-J).length();var energy0=.5*m*b.linear_velocity.dot(b.linear_velocity)+m*g*b.position.y;var energy1=.5*m*actual.linear_velocity.dot(actual.linear_velocity)+m*g*actual.position.y;var energy_error=abs(energy1-energy0+normal_loss+impact_loss+support_loss)
                var valid=error==0 and pe<=1e-10*(1+expected_p.length()) and ve<=1e-10*(1+expected_v.length()) and momentum<=1e-10*(1+J.length()) and energy_error<=1e-9*(1+abs(energy0)) and actual.angular_velocity.length()<=1e-10 and abs(actual.orientation.x)+abs(actual.orientation.y)+abs(actual.orientation.z)<=1e-10 and actual.force.length()==0 and actual.torque.length()==0
                if kind==0:valid=valid and float_bits(actual.linear_velocity.y)==float_bits(r[9]) and r[39]==0 and r[40]==0 and summary[2]==1
                if kind==1 or kind==3 or kind==5 or kind==6:valid=valid and float_bits(actual.linear_velocity.y)==float_bits(vy) and r[5]==0 and r[32]==0 and r[33]==0 and summary[2]==0
                if kind==7 or kind==10:valid=valid and summary[2]==1 and abs(r[10]-t)<=1e-10 and r[11]<=1e-9
                if kind==8:valid=valid and r[43]>0 and summary[2]==0
                if error!=0:
                    bits_equal(before,after)
                    with gpu._episode.map_to_host() as e,gpu._last.map_to_host() as l:
                        for i in range(16):assert_equal(UInt64(e[i]),ep0[i])
                        for i in range(48):assert_equal(float_bits(Float64(l[i])),ep0[16+i])
                var next=gpu.world.bodies.metadata()
                for i in range(len(meta)):assert_equal(meta[i],next[i])
                file.write('{"variant":'+String(variant)+',"kind":'+String(kind)+',"order":'+String(order)+',"error":'+String(error)+',"initial_vy":'+String(vy)+',"gravity":'+String(g)+',"expected_return_time":'+String(t)+',"expected_hit":'+String(Int(hit))+',"actual":'+json_values(values)+',"stats":'+json_values(stats)+',"summary":'+json_values(summary)+',"position_error":'+String(pe)+',"velocity_error":'+String(ve)+',"momentum_error":'+String(momentum)+',"energy_error":'+String(energy_error)+',"physical_pass":'+String(Int(valid))+'}\n');gpu.close();assert_true(valid,"STOP: unilateral boundary physical failure")
    print("UNILATERAL_BOUNDARY_ANALYTIC_PASS",variant,24)
