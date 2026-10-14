"""Isolated certified monotone all-vertex sweep; no contact impulse or episode owner."""
from std.collections import Array
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,advance,momentum
from .response_kernels import body_profile,kinetic

def sweep_pose(b: BodyState, acceleration: Vec3, t: Float64) -> BodyState:
    var trial=b
    trial.position=b.position+b.linear*t+acceleration*(.5*t*t)
    trial.linear=b.linear+acceleration*t
    trial.orientation=advance(b.orientation,b.angular,t).q
    return trial

def rotating_monotone_toi(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    # Slots 1..38 are the old impulse payload; 40=horizon, 41..43=gravity.
    # No descriptor/force/episode is consumed. State is published only at success.
    for i in range(1,95):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=43 else 0.0
    output[unsafe_offset=39]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor_y=inputs[unsafe_offset=34]
    var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not body_profile(b) or b.mass<=0 or not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor_y) or abs(floor_y)>1000:output[unsafe_offset=39]=700;return
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0:output[unsafe_offset=39]=701;return
    var H=inputs[unsafe_offset=40];var gravity=Vec3(inputs[unsafe_offset=41],inputs[unsafe_offset=42],inputs[unsafe_offset=43]);var e=inputs[unsafe_offset=36];var episode=inputs[unsafe_offset=37];var enumeration=inputs[unsafe_offset=38]
    if not isfinite(H) or H<=0 or H>1.0/30 or not finite(gravity) or b.angular.length()*H>.25 or not isfinite(e) or e<0 or e>1 or (episode!=0 and episode!=1) or not isfinite(enumeration) or enumeration<0 or enumeration>15 or enumeration!=Float64(Int(enumeration)):output[unsafe_offset=39]=702;return
    var acceleration=gravity+b.force*(1/b.mass)
    if not finite(acceleration):output[unsafe_offset=39]=702;return
    var local=Array[Vec3,8](fill=Vec3(0,0,0));var initial=Float64(1e30);var radius=Float64(0)
    for i in range(8):
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z)
        local[i]=center+shape.rotate(corner);radius=max(radius,local[i].length());initial=min(initial,b.position.y+b.orientation.rotate(local[i]).y-floor_y)
    if initial<=1e-9:output[unsafe_offset=39]=703;return
    # |(omega x r).y| <= |omega||r| at EVERY time. A conservative strictly
    # negative bound makes every gap monotone, proving absence of earlier roots.
    var bound=b.linear.y+max(0.0,acceleration.y*H)+b.angular.length()*radius
    if not isfinite(bound) or bound>=-1e-9*(1+abs(b.linear.y)+b.angular.length()*radius):output[unsafe_offset=39]=704;return
    var endpoint=sweep_pose(b,acceleration,H);var t=H;var hit=False;var endpoint_gap=Float64(1e30)
    for visit in range(8):
        var i=(visit+Int(enumeration)%8)%8 if enumeration<8 else (7-visit+Int(enumeration)%8)%8
        var gap=endpoint.position.y+endpoint.orientation.rotate(local[i]).y-floor_y;endpoint_gap=min(endpoint_gap,gap)
        if gap<=0:
            var lo=Float64(0);var hi=H
            for _ in range(64):
                var mid=lo+(hi-lo)*.5;var at=sweep_pose(b,acceleration,mid);var value=at.position.y+at.orientation.rotate(local[i]).y-floor_y
                if value>0:lo=mid
                else:hi=mid
            t=min(t,hi);hit=True
    var trial=sweep_pose(b,acceleration,t);var best=Float64(1e30);var selected=8
    for i in range(8):
        var arm=trial.orientation.rotate(local[i]);var gap=trial.position.y+arm.y-floor_y
        output[unsafe_offset=60+i]=gap;output[unsafe_offset=68+i]=(trial.linear+trial.angular.cross(arm)).y
        if gap<best or (gap==best and i<selected):best=gap;selected=i
    var second=Float64(1e30)
    for i in range(8):
        if i!=selected:second=min(second,output[unsafe_offset=60+i])
    if hit and second<=1e-9:output[unsafe_offset=39]=705;return
    if not body_profile(trial) or (hit and abs(best)>1e-9) or (not hit and best<=0):output[unsafe_offset=39]=706;return
    var work=(b.force+gravity*b.mass).dot(trial.position-b.position);var energy_error=abs(kinetic(trial)-kinetic(b)-work);var angular_error=(momentum(trial.orientation,trial.inertia,trial.angular)-momentum(b.orientation,b.inertia,b.angular)).length()
    if energy_error>1e-9*(1+kinetic(b)) or angular_error>1e-10*(1+momentum(b.orientation,b.inertia,b.angular).length()):output[unsafe_offset=39]=707;return
    output[unsafe_offset=44]=Float64(Int(hit));output[unsafe_offset=45]=t;output[unsafe_offset=46]=initial;output[unsafe_offset=47]=endpoint_gap;output[unsafe_offset=48]=bound;output[unsafe_offset=49]=Float64(selected);output[unsafe_offset=50]=best;output[unsafe_offset=51]=second;output[unsafe_offset=52]=work;output[unsafe_offset=53]=energy_error;output[unsafe_offset=54]=angular_error
    output[unsafe_offset=5]=trial.position.x;output[unsafe_offset=6]=trial.position.y;output[unsafe_offset=7]=trial.position.z;output[unsafe_offset=8]=trial.orientation.x;output[unsafe_offset=9]=trial.orientation.y;output[unsafe_offset=10]=trial.orientation.z;output[unsafe_offset=11]=trial.orientation.w;output[unsafe_offset=12]=trial.linear.x;output[unsafe_offset=13]=trial.linear.y;output[unsafe_offset=14]=trial.linear.z
