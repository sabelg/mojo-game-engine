"""Transactional instantaneous handoff; no timestep, cached geometry or warm start."""
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite
from .response_kernels import body_profile
from .two_point_inelastic import two_point_inelastic
from .two_point_reaction import two_point_reaction

def handoff_bits(value: Float64) -> UInt64:
    var stored=value
    return Pointer[UInt64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=stored)))[]

def floor_handoff(inputs: Pointer[Float64,MutAnyOrigin],previous: Pointer[Float64,MutAnyOrigin],request: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin],scratch: Pointer[Float64,MutAnyOrigin],status: Pointer[Float64,MutAnyOrigin]):
    # Entire owner rollback, including last impulse history, on every failure.
    for i in range(128):output[unsafe_offset=i]=previous[unsafe_offset=i]
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var epoch=previous[unsafe_offset=96];var revision=previous[unsafe_offset=97]
    if not isfinite(epoch) or epoch<0 or epoch>=1000000 or epoch!=Float64(Int(epoch)) or not isfinite(revision) or revision<0 or revision>=1000000 or revision!=Float64(Int(revision)) or request[unsafe_offset=0]!=epoch:status[unsafe_offset=0]=1300;return
    var changed=False
    for i in range(1,45):
        if i!=39 and handoff_bits(inputs[unsafe_offset=i])!=handoff_bits(previous[unsafe_offset=i]):changed=True
    var required=revision+1 if changed or epoch==0 else revision
    if request[unsafe_offset=1]!=required:status[unsafe_offset=0]=1301;return
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    if not body_profile(b) or b.mass<=0:status[unsafe_offset=0]=1200;return
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor=inputs[unsafe_offset=34];var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor) or abs(floor)>1000:status[unsafe_offset=0]=1201;return
    var order=inputs[unsafe_offset=38]
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0 or inputs[unsafe_offset=36]!=0 or (inputs[unsafe_offset=37]!=0 and inputs[unsafe_offset=37]!=1) or not isfinite(order) or order<0 or order>15 or order!=Float64(Int(order)):status[unsafe_offset=0]=1202;return

    var gravity=Vec3(inputs[unsafe_offset=42],inputs[unsafe_offset=43],inputs[unsafe_offset=44])
    if not finite(gravity) or component(gravity)>1000 or component(b.force)>1000*b.mass:status[unsafe_offset=0]=1206;return
    var touches=0;var first=0;var second=0;var low=Float64(1e30);var high=Float64(-1e30)
    for i in range(8):
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z);var arm=b.orientation.rotate(center+shape.rotate(corner));var gap=b.position.y+arm.y-floor;var vn=(b.linear+b.angular.cross(arm)).y
        if not isfinite(gap) or gap < -1e-9:status[unsafe_offset=0]=1302;return
        if gap<=1e-9:
            if touches==0:first=i
            else:second=i
            touches+=1;low=min(low,vn);high=max(high,vn)
    if touches>2:status[unsafe_offset=0]=1303;return
    var phase=5;var impacted=False
    for i in range(96):scratch[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=44 or i==95 else 0
    scratch[unsafe_offset=39]=0
    if touches==1:phase=6
    elif touches==2:
        var f0=inputs[unsafe_offset=40];var f1=inputs[unsafe_offset=41]
        if not ((f0==Float64(first) and f1==Float64(second)) or (f1==Float64(first) and f0==Float64(second))):status[unsafe_offset=0]=1303;return
        if low < -1e-9:
            if high>1e-9:status[unsafe_offset=0]=1304;return
            two_point_inelastic(scratch,scratch+96)
            if scratch[unsafe_offset=135]!=0:status[unsafe_offset=0]=1305;status[unsafe_offset=1]=scratch[unsafe_offset=135];return
            for i in range(12,18):scratch[unsafe_offset=i]=scratch[unsafe_offset=96+i]
            impacted=True
        elif high>1e-9:
            phase=4 if low>1e-9 else 6
        if impacted or high<=1e-9:
            # The reaction primitive rebuilds all geometry and actual point velocities.
            two_point_reaction(scratch,scratch+192)
            if scratch[unsafe_offset=231]!=0:status[unsafe_offset=0]=1306;status[unsafe_offset=1]=scratch[unsafe_offset=231];return
            var N0=scratch[unsafe_offset=238];var N1=scratch[unsafe_offset=239];var a0=scratch[unsafe_offset=242];var a1=scratch[unsafe_offset=243];var tolerance=scratch[unsafe_offset=248]
            # A zero reaction with uncertified opening is an unresolved active-set boundary.
            if (N0==0 and a0<=tolerance) or (N1==0 and a1<=tolerance):status[unsafe_offset=0]=1307;return
            phase=1 if N0>0 and N1>0 else 2 if N0>0 or N1>0 else 3
            for i in range(45,95):scratch[unsafe_offset=i]=scratch[unsafe_offset=192+i]
    # Commit only after the entire impact-to-reaction transaction passes.
    for i in range(96):output[unsafe_offset=i]=scratch[unsafe_offset=i]
    output[unsafe_offset=96]=epoch+1;output[unsafe_offset=97]=required;output[unsafe_offset=98]=Float64(phase)
    output[unsafe_offset=102]=0;output[unsafe_offset=103]=0;output[unsafe_offset=104]=0
    if impacted:
        output[unsafe_offset=99]=previous[unsafe_offset=99]+1
        output[unsafe_offset=100]=scratch[unsafe_offset=140];output[unsafe_offset=101]=scratch[unsafe_offset=141]
        output[unsafe_offset=102]=scratch[unsafe_offset=140];output[unsafe_offset=103]=scratch[unsafe_offset=141];output[unsafe_offset=104]=scratch[unsafe_offset=154]
    output[unsafe_offset=105]=Float64(touches)
