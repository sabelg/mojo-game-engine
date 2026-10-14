"""Genuine consecutive1second friction trajectories with independent analytic events."""
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
    with open(args[1]+"-frames.jsonl","w") as file:
        for kind in range(12):
            var gpu=GpuUnilateralTemporalFloorFrictionAdvance(point_order=Int32(0 if variant%2==0 else 11));var fh=gpu.world.bodies.submit([BodyCommand.create(RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,-.25,0)))]);_=gpu.world.submit_boxes([BoxCommand.attach(fh[0],Vec3(5,.25,5))]);var d=Vec3(1,0,0);var u=Float64(.3);var g=Float64(9.81);var mu=Float64(.2);var e=Float64(0);var at=Float64(0);var y=half.y;var vn=Float64(0)
            if kind==1:d=Vec3(.6,0,.8);u=.5
            if kind==2:u=0;at=.8*mu*g
            if kind==3:d=Vec3(.6,0,.8);u=0;at=1.2*mu*g
            if kind==4:u=.02;at=.5*mu*g
            if kind==5:u=.04;at=-.5*mu*g
            if kind>=6 and kind<=9:d=Vec3(.6,0,.8);u=.5;y+=.002;vn=-1
            if kind==7:e=.5
            if kind==8:e=1
            if kind==9 or kind==10:g=0
            if kind==10:vn=5.551115123125783e-17
            if kind==11:mu=0
            var initial_u=u;var initial_y=y;var initial_vn=vn;var b=RigidBody3D(MassProperties3D(m,I),position=Vec3(0,y,0));b.linear_velocity=d*u+Vec3(0,vn,0);var bh=gpu.world.bodies.submit([BodyCommand.create(b)]);var shapes=gpu.world.submit_boxes([BoxCommand.attach(bh[0],half)]);var distance=Float64(0);var loss=Float64(0);var total_TOI=0;var measured_TOI=0;var total_stops=0;var measured_stops=0
            for frame in range(30):
                var u_entry=u;var vn_entry=vn;var distance_entry=distance;var loss_entry=loss;var remaining=H;var expected_TOI=0;var expected_stop=0
                # Exact scalar flight/impact/constant-direction Coulomb dynamics.
                # No production GPU/core/friction helper is used by this oracle.
                for event in range(20):
                    if remaining<=0:break
                    if y==half.y and vn==0:
                        var drag=mu*g
                        if u==0:
                            var a=max(0.0,at-drag);var dx=.5*a*remaining*remaining;distance+=dx;u=a*remaining;loss+=mu*m*g*dx;remaining=0;break
                        var decel=drag-at;var duration=remaining;var stopped=False
                        if decel>0:
                            var t=u/decel
                            if t<=remaining:duration=t;expected_stop+=1;stopped=True
                        var dx=u*duration-.5*decel*duration*duration;distance+=dx;loss+=mu*m*g*dx;u=0.0 if stopped else max(0.0,u-decel*duration);remaining-=duration
                        if u==0:remaining=0
                        continue
                    var gap=y-half.y;var t=remaining+1
                    if g>0:t=(vn+sqrt(vn*vn+2*g*max(0.0,gap)))/g
                    elif vn<0:t=gap/(-vn)
                    var hit=t>=0 and t<=remaining;var duration=t if hit else remaining;distance+=u*duration+.5*at*duration*duration;u+=at*duration;y+=vn*duration-.5*g*duration*duration;vn-=g*duration;remaining-=duration
                    if not hit:break
                    var V=-vn;var beta=e*V if V>.2 else 0.0;var post=max(0.0,u-mu*(V+beta));loss+=.5*m*(V*V-beta*beta+u*u-post*post);u=post;vn=beta;y=half.y;expected_TOI+=1
                assert_true(remaining<=1e-14);total_TOI+=expected_TOI;total_stops+=expected_stop
                _=gpu.world.bodies.submit([BodyCommand.force(bh[0],d*(m*at))]);var before=gpu.world.bodies.raw();var meta=gpu.world.bodies.metadata();var ep0=List[UInt64]()
                with gpu._episode.map_to_host() as a,gpu._last.map_to_host() as l:
                    for i in range(16):ep0.append(UInt64(a[i]))
                    for i in range(48):ep0.append(float_bits(Float64(l[i])))
                var error=gpu.advance(gravity=Vec3(0,-g,0),coefficient=mu,restitution=e);var after=gpu.world.bodies.raw();var actual=decode(after,Int(bh[0].slot));var r=gpu.report();var sums=List[Float64]();var stats=List[Float64]();var av=state_words(body_state(actual));var values=List[Float64]()
                with gpu._summary.map_to_host() as a:
                    for i in range(6):sums.append(Float64(a[i]))
                measured_TOI+=Int(sums[2]);measured_stops+=Int(r[34])
                for i in range(62):stats.append(r[i])
                for i in range(23):values.append(av[i])
                var p=d*distance+Vec3(0,y,0);var v=d*u+Vec3(0,vn,0);var pe=(actual.position-p).length();var ve=(actual.linear_velocity-v).length();var entry=decode(before,Int(bh[0].slot));var J=Vec3(r[32],r[5],r[33]);var momentum=((actual.linear_velocity-entry.linear_velocity)*m-d*(m*at*H)-Vec3(0,-m*g*H,0)-J).length();var energy0=.5*m*(initial_u*initial_u+initial_vn*initial_vn)+m*g*initial_y;var energy1=.5*m*actual.linear_velocity.dot(actual.linear_velocity)+m*g*actual.position.y;var energy_error=abs(energy1-energy0-m*at*distance+loss)
                var valid=error==0 and pe<=1e-10*(1+p.length()) and ve<=1e-10*(1+v.length()) and actual.angular_velocity.length()<=1e-10 and abs(actual.orientation.x)+abs(actual.orientation.y)+abs(actual.orientation.z)<=1e-10 and momentum<=1e-10*(1+J.length()) and energy_error<=1e-9*(1+abs(energy0)+abs(m*at*distance)+loss) and actual.force.length()==0 and actual.torque.length()==0 and measured_TOI==total_TOI and measured_stops==total_stops
                if error!=0:
                    bits_equal(before,after)
                    with gpu._episode.map_to_host() as a,gpu._last.map_to_host() as l:
                        for i in range(16):assert_equal(UInt64(a[i]),ep0[i])
                        for i in range(48):assert_equal(float_bits(Float64(l[i])),ep0[16+i])
                var next=gpu.world.bodies.metadata()
                for i in range(len(meta)):assert_equal(meta[i],next[i])
                file.write('{"variant":'+String(variant)+',"kind":'+String(kind)+',"frame":'+String(frame)+',"error":'+String(error)+',"mass":'+String(m)+',"gravity":'+String(g)+',"mu":'+String(mu)+',"e":'+String(e)+',"force_acceleration":'+String(at)+',"expected_distance":'+String(distance)+',"expected_speed":'+String(u)+',"expected_y":'+String(y)+',"expected_vy":'+String(vn)+',"expected_TOI_total":'+String(total_TOI)+',"measured_TOI_total":'+String(measured_TOI)+',"expected_stops_total":'+String(total_stops)+',"measured_stops_total":'+String(measured_stops)+',"actual":'+json_values(values)+',"stats":'+json_values(stats)+',"summary":'+json_values(sums)+',"position_error":'+String(pe)+',"velocity_error":'+String(ve)+',"momentum_error":'+String(momentum)+',"energy_error":'+String(energy_error)+',"physical_pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: first substantive repeated-trajectory physical failure")
            gpu.close()
    print("UNILATERAL_GENUINE_ONE_SECOND_ANALYTIC_PASS",variant,360)
