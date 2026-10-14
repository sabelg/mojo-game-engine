"""Isolated fixed-budget conservative interval sweep; unresolved grazing rejects."""
from std.collections import Array
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,advance,momentum
from .response_kernels import body_profile,kinetic

from .rotating_monotone_toi import sweep_pose

def rotating_subdivision_toi(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    # Slots 1..38 are the old impulse payload; 40=horizon, 41..43=gravity.
    # No descriptor/force/episode is consumed. State is published only at success.
    for i in range(1,95):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=43 else 0.0
    output[unsafe_offset=39]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor_y=inputs[unsafe_offset=34]
    var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not body_profile(b) or b.mass<=0 or not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor_y) or abs(floor_y)>1000:output[unsafe_offset=39]=800;return
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0:output[unsafe_offset=39]=801;return
    var H=inputs[unsafe_offset=40];var gravity=Vec3(inputs[unsafe_offset=41],inputs[unsafe_offset=42],inputs[unsafe_offset=43]);var e=inputs[unsafe_offset=36];var episode=inputs[unsafe_offset=37];var enumeration=inputs[unsafe_offset=38]
    if not isfinite(H) or H<=0 or H>1.0/30 or not finite(gravity) or b.angular.length()*H>.25 or not isfinite(e) or e<0 or e>1 or (episode!=0 and episode!=1) or not isfinite(enumeration) or enumeration<0 or enumeration>15 or enumeration!=Float64(Int(enumeration)):output[unsafe_offset=39]=802;return
    var acceleration=gravity+b.force*(1/b.mass)
    if not finite(acceleration):output[unsafe_offset=39]=802;return
    var local=Array[Vec3,8](fill=Vec3(0,0,0));var initial=Float64(1e30);var radius=Float64(0)
    for i in range(8):
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z)
        local[i]=center+shape.rotate(corner);radius=max(radius,local[i].length());initial=min(initial,b.position.y+b.orientation.rotate(local[i]).y-floor_y)
    if initial < -1e-9:output[unsafe_offset=39]=803;return
    # Norm inflation covers admitted orientation normalization/roundoff error.
    var bound=(abs(acceleration.y)+b.angular.dot(b.angular)*radius)*(1+1e-8)
    var envelope=256*2.220446049250313e-16*(1+abs(b.position.y)+abs(floor_y)+radius+abs(b.linear.y)*H+abs(acceleration.y)*H*H)
    var velocity_envelope=256*2.220446049250313e-16*(1+abs(b.linear.y)+abs(acceleration.y)*H+b.angular.length()*radius)
    if not isfinite(bound) or not isfinite(envelope):output[unsafe_offset=39]=802;return
    var touching=0
    for i in range(8):
        var r=b.orientation.rotate(local[i]);var gap=b.position.y+r.y-floor_y;var speed=(b.linear+b.angular.cross(r)).y
        if gap<=1e-9:
            touching+=1
            if speed<=1e-9*(1+abs(b.linear.y)+b.angular.length()*radius):output[unsafe_offset=39]=808;return
    if touching>1:output[unsafe_offset=39]=805;return
    var endpoint=sweep_pose(b,acceleration,H);var t=H;var hit=False;var endpoint_gap=Float64(1e30)
    for visit in range(8):
        var i=(visit+Int(enumeration)%8)%8 if enumeration<8 else (7-visit+Int(enumeration)%8)%8
        var re=endpoint.orientation.rotate(local[i]);endpoint_gap=min(endpoint_gap,endpoint.position.y+re.y-floor_y)
        var left=Float64(0);var gl=b.position.y+b.orientation.rotate(local[i]).y-floor_y
        for cell in range(64):
            var right=H*Float64(cell+1)/64;var width=right-left
            var at=sweep_pose(b,acceleration,right);var gr=at.position.y+at.orientation.rotate(local[i]).y-floor_y
            var mid=left+width*.5;var middle=sweep_pose(b,acceleration,mid)
            var um=(middle.linear+b.angular.cross(middle.orientation.rotate(local[i]))).y
            var lower_speed=um-bound*width*.5-velocity_envelope;var upper_speed=um+bound*width*.5+velocity_envelope
            # Linear interpolation error bound covers interior minima even when
            # both endpoints are positive. Never use endpoint signs alone.
            if min(gl,gr)-bound*width*width/8 > envelope:
                pass
            elif lower_speed>0 and (gl>envelope or (cell==0 and gl>=-1e-9)):
                pass
            elif upper_speed<0 and gl>envelope:
                if gr < -envelope:
                    var lo=left;var hi=right
                    for _ in range(64):
                        var center_t=lo+(hi-lo)*.5;var q=sweep_pose(b,acceleration,center_t)
                        var value=q.position.y+q.orientation.rotate(local[i]).y-floor_y
                        if value>0:lo=center_t
                        else:hi=center_t
                    t=min(t,hi);hit=True;break
                elif gr<=envelope:
                    output[unsafe_offset=39]=811;return
            else:
                # Finite budget exhausted without an interval certificate:
                # numerical uncertainty/tangency/insufficient subdivision.
                output[unsafe_offset=39]=811;return
            left=right;gl=gr
    var trial=sweep_pose(b,acceleration,t);var best=Float64(1e30);var selected=8
    for i in range(8):
        var arm=trial.orientation.rotate(local[i]);var gap=trial.position.y+arm.y-floor_y
        output[unsafe_offset=60+i]=gap;output[unsafe_offset=68+i]=(trial.linear+trial.angular.cross(arm)).y
        if gap<best or (gap==best and i<selected):best=gap;selected=i
    var second=Float64(1e30)
    for i in range(8):
        if i!=selected:second=min(second,output[unsafe_offset=60+i])
    if hit and second<=1e-9:output[unsafe_offset=39]=805;return
    if not body_profile(trial) or (hit and abs(best)>1e-9) or (not hit and best<=0):output[unsafe_offset=39]=806;return
    if hit:
        var closing= -output[unsafe_offset=68+selected]
        # Reject poorly conditioned Float64 roots rather than claim accurate time.
        var evaluation_envelope=256*2.220446049250313e-16*(1+abs(b.position.y)+abs(floor_y)+radius+abs(b.linear.y)*H+abs(acceleration.y)*H*H)
        if closing<=0 or evaluation_envelope/closing>1e-11:output[unsafe_offset=39]=810;return
    output[unsafe_offset=56]=Float64(touching);output[unsafe_offset=57]=0.0
    output[unsafe_offset=58]=0.0
    var work=(b.force+gravity*b.mass).dot(trial.position-b.position);var energy_error=abs(kinetic(trial)-kinetic(b)-work);var angular_error=(momentum(trial.orientation,trial.inertia,trial.angular)-momentum(b.orientation,b.inertia,b.angular)).length()
    if energy_error>1e-9*(1+kinetic(b)) or angular_error>1e-10*(1+momentum(b.orientation,b.inertia,b.angular).length()):output[unsafe_offset=39]=807;return
    output[unsafe_offset=44]=Float64(Int(hit));output[unsafe_offset=45]=t;output[unsafe_offset=46]=initial;output[unsafe_offset=47]=endpoint_gap;output[unsafe_offset=48]=bound;output[unsafe_offset=49]=Float64(selected);output[unsafe_offset=50]=best;output[unsafe_offset=51]=second;output[unsafe_offset=52]=work;output[unsafe_offset=53]=energy_error;output[unsafe_offset=54]=angular_error
    output[unsafe_offset=5]=trial.position.x;output[unsafe_offset=6]=trial.position.y;output[unsafe_offset=7]=trial.position.z;output[unsafe_offset=8]=trial.orientation.x;output[unsafe_offset=9]=trial.orientation.y;output[unsafe_offset=10]=trial.orientation.z;output[unsafe_offset=11]=trial.orientation.w;output[unsafe_offset=12]=trial.linear.x;output[unsafe_offset=13]=trial.linear.y;output[unsafe_offset=14]=trial.linear.z
