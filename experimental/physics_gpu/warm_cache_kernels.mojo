"""Seeds-disabled opt-in cache plumbing. Never writes solver packing or bodies."""
from std.memory import Pointer
from std.collections import Array
from std.math import isfinite,sqrt
from mojo_game import Vec3,Quaternion
from .kernels import CAPACITY,load
from .lifecycle_kernels import UPDATE
from .shape_kernels import vi,POISON
from .core import rotation,finite
from .friction_kernels import tangent_axes
from .box_box import float_bits

comptime WP=18
comptime WF=9
comptime WPOINT=10
comptime WMETA=12

def initialize_tracking(revisions: Pointer[UInt64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],dt: Pointer[Float64,MutAnyOrigin]):
    for i in range(CAPACITY):revisions[unsafe_offset=1+i]=0
    for i in range(1,8):state[unsafe_offset=i]=0
    state[unsafe_offset=6]=1;dt[unsafe_offset=1]=0

def track_commands(headers: Pointer[UInt64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],revisions: Pointer[UInt64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],count: Int32):
    if summary[unsafe_offset=0]!=0 or state[unsafe_offset=6]==0:return
    for i in range(Int(count)):
        var h=1+i*4
        if headers[unsafe_offset=h]!=UPDATE:continue
        var slot=Int(headers[unsafe_offset=h+1]);var old=revisions[unsafe_offset=1+slot]
        if old==UInt64.MAX:state[unsafe_offset=6]=0;return
        revisions[unsafe_offset=1+slot]=old+1

def track_integration(summary: Pointer[Int32,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],dt: Pointer[Float64,MutAnyOrigin],step_dt: Float64):
    if summary[unsafe_offset=0]!=0 or state[unsafe_offset=6]==0:return
    if state[unsafe_offset=1]==UInt64.MAX:state[unsafe_offset=6]=0;return
    state[unsafe_offset=1]+=1;dt[unsafe_offset=1]=step_dt

def warm_begin(state: Pointer[UInt64,MutAnyOrigin],pending: Pointer[UInt64,MutAnyOrigin],mapping: Pointer[Int32,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin]):
    for i in range(1,WMETA-1):pending[unsafe_offset=i]=0
    for i in range(64):mapping[unsafe_offset=1+i]=-1
    for i in range(1,19):diagnostic[unsafe_offset=i]=0
    state[unsafe_offset=7]=0
    if state[unsafe_offset=6]!=0:
        if state[unsafe_offset=4]<UInt64.MAX and state[unsafe_offset=5]==1 and state[unsafe_offset=2]==state[unsafe_offset=3] and state[unsafe_offset=1]==state[unsafe_offset=4]+1:state[unsafe_offset=7]=1
        if state[unsafe_offset=2]==UInt64.MAX:state[unsafe_offset=6]=0;state[unsafe_offset=7]=0
        else:state[unsafe_offset=2]+=1
    state[unsafe_offset=5]=0

# Canonical low/high are ordered by body slot within this namespace. The cached
# normal points low->high, anchors follow low/high, and J_t is impulse on high.
# Solver A/B ordering and every packed solver array remain untouched.
def warm_key(headers: Pointer[UInt64,MutAnyOrigin],point: Int) -> Array[UInt64,11]:
    var h=1+point*11;var result=Array[UInt64,11](fill=0);var reverse=headers[unsafe_offset=h+3]>headers[unsafe_offset=h+8]
    for i in range(5):
        result[i]=headers[unsafe_offset=h+(5 if reverse else 0)+i]
        result[5+i]=headers[unsafe_offset=h+(0 if reverse else 5)+i]
    result[10]=headers[unsafe_offset=h+10];return result^

def warm_feature(feature: UInt64,reverse: Bool) -> UInt64:
    if not reverse:return feature
    if feature<3:return feature+3
    if feature<6:return feature-3
    return 6+((feature-6)%3)*3+(feature-6)//3

def warm_local(pose: Quaternion,position: Vec3,witness: Vec3) -> Vec3:
    var q=rotation(pose);return Quaternion(-q.x,-q.y,-q.z,q.w).rotate(witness-position)

def warm_prepare(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],features: Pointer[UInt64,MutAnyOrigin],descriptors: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],revisions: Pointer[UInt64,MutAnyOrigin],tracking: Pointer[UInt64,MutAnyOrigin],integration_dt: Pointer[Float64,MutAnyOrigin],current_h: Pointer[UInt64,MutAnyOrigin],current_f: Pointer[Float64,MutAnyOrigin],current_p: Pointer[Float64,MutAnyOrigin],current_m: Pointer[UInt64,MutAnyOrigin],pending_h: Pointer[UInt64,MutAnyOrigin],pending_f: Pointer[Float64,MutAnyOrigin],pending_p: Pointer[Float64,MutAnyOrigin],pending_m: Pointer[UInt64,MutAnyOrigin],mapping: Pointer[Int32,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin],dt: Float64,e: Float64,mu: Float64,vi_count: Int32,pi_count: Int32,budget: Int32,cache_patches: Int32,cache_points: Int32,c: Float64,s: Float64):
    for i in range(16*WP):pending_h[unsafe_offset=1+i]=UInt64.MAX
    for i in range(16*WF):pending_f[unsafe_offset=1+i]=POISON
    for i in range(64*WPOINT):pending_p[unsafe_offset=1+i]=POISON
    if summary[unsafe_offset=0]!=0:return
    pending_m[unsafe_offset=3]=tracking[unsafe_offset=1];pending_m[unsafe_offset=4]=tracking[unsafe_offset=2]
    pending_m[unsafe_offset=5]=float_bits(dt);pending_m[unsafe_offset=6]=float_bits(e);pending_m[unsafe_offset=7]=float_bits(mu)
    pending_m[unsafe_offset=8]=UInt64(vi_count);pending_m[unsafe_offset=9]=UInt64(pi_count);pending_m[unsafe_offset=10]=UInt64(budget)
    var epoch_ok=tracking[unsafe_offset=6]!=0 and tracking[unsafe_offset=7]!=0 and current_m[unsafe_offset=3]<UInt64.MAX and current_m[unsafe_offset=3]+1==tracking[unsafe_offset=1] and current_m[unsafe_offset=4]+1==tracking[unsafe_offset=2]
    var material_ok=float_bits(integration_dt[unsafe_offset=1])==float_bits(dt)
    for i in range(5,11):material_ok=material_ok and current_m[unsafe_offset=i]==pending_m[unsafe_offset=i]
    # Repeated resolves at the same integration epoch publish an empty cache;
    # rejected attempts preserve bytes but warm_begin breaks eligibility.
    var publish_allowed=tracking[unsafe_offset=6]!=0 and tracking[unsafe_offset=1]>0 and tracking[unsafe_offset=1]!=tracking[unsafe_offset=4] and float_bits(integration_dt[unsafe_offset=1])==float_bits(dt)
    for patch in range(Int(summary[unsafe_offset=3])):
        diagnostic[unsafe_offset=1]+=1
        var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var key=warm_key(headers,start)
        var reverse=headers[unsafe_offset=1+start*11+3]>headers[unsafe_offset=1+start*11+8];var sign=Float64(-1) if reverse else Float64(1)
        var shape_a=Int(headers[unsafe_offset=1+start*11]);var shape_b=Int(headers[unsafe_offset=1+start*11+5]);var pair=shape_a*(128-shape_a-1)//2+shape_b-shape_a-1
        var feature=warm_feature(features[unsafe_offset=1+pair*2],reverse);var flags=features[unsafe_offset=2+pair*2]
        var g=1+start*10;var n=Vec3(geometry[unsafe_offset=g],geometry[unsafe_offset=g+1],geometry[unsafe_offset=g+2])*sign
        var basis=tangent_axes(n,c,s)
        var a=load(candidate,Int(key[3]));var b=load(candidate,Int(key[8]));var anchors=Array[Float64,24](fill=0)
        for i in range(count):
            var k=1+(start+i)*10;var wa=Vec3(geometry[unsafe_offset=k+4],geometry[unsafe_offset=k+5],geometry[unsafe_offset=k+6]);var wb=Vec3(geometry[unsafe_offset=k+7],geometry[unsafe_offset=k+8],geometry[unsafe_offset=k+9])
            var aa=warm_local(a.orientation,a.position,wb if reverse else wa);var bb=warm_local(b.orientation,b.position,wa if reverse else wb)
            anchors[i*6]=aa.x;anchors[i*6+1]=aa.y;anchors[i*6+2]=aa.z;anchors[i*6+3]=bb.x;anchors[i*6+4]=bb.y;anchors[i*6+5]=bb.z
        var capacity_ok=Int(pending_m[unsafe_offset=1])<Int(cache_patches) and Int(pending_m[unsafe_offset=2])+count<=Int(cache_points)
        var old=-1
        if not epoch_ok:diagnostic[unsafe_offset=3]+=1
        elif not material_ok:diagnostic[unsafe_offset=5]+=1
        else:
            for p in range(Int(current_m[unsafe_offset=1])):
                var h=1+p*WP;var equal=True
                for i in range(11):equal=equal and current_h[unsafe_offset=h+i]==key[i]
                equal=equal and current_h[unsafe_offset=h+15]==revisions[unsafe_offset=1+Int(key[3])] and current_h[unsafe_offset=h+16]==revisions[unsafe_offset=1+Int(key[8])]
                if equal:
                    if old>=0:old=-2;break
                    old=p
            if old<0:diagnostic[unsafe_offset=4]+=1
        var hit=old>=0 and capacity_ok
        var matches=Array[Int,4](fill=-1);var used=Array[Bool,4](fill=False)
        if hit:
            var h=1+old*WP;var f=1+old*WF
            if flags!=0 or current_h[unsafe_offset=h+12]!=0 or feature!=current_h[unsafe_offset=h+11] or count!=Int(current_h[unsafe_offset=h+13]):hit=False;diagnostic[unsafe_offset=6]+=1
            var old_n=Vec3(current_f[unsafe_offset=f],current_f[unsafe_offset=f+1],current_f[unsafe_offset=f+2])
            if not finite(n) or not finite(old_n) or abs(n.dot(n)-1)>1e-12 or abs(old_n.dot(old_n)-1)>1e-12 or n.dot(old_n)<.9999:hit=False;diagnostic[unsafe_offset=7]+=1
            if hit:
                var extent=Float64(10)
                for shape in range(2):
                    var slot=shape_a if shape==0 else shape_b
                    for axis in range(4,7):extent=min(extent,vi(descriptors,axis,slot))
                var band=.05*extent;var old_start=Int(current_h[unsafe_offset=h+14]);var ambiguous=False
                for i in range(count):
                    var found=-1
                    for j in range(count):
                        var close=True
                        for side in range(2):
                            var distance=Float64(0)
                            for axis in range(3):
                                var delta=anchors[i*6+side*3+axis]-current_p[unsafe_offset=1+(old_start+j)*WPOINT+side*3+axis];distance+=delta*delta
                            close=close and isfinite(distance) and distance<=band*band
                        if close:
                            if found>=0:ambiguous=True
                            found=j
                    if found<0:hit=False
                    elif used[max(found,0)]:ambiguous=True
                    else:used[found]=True;matches[i]=old_start+found
                for i in range(count):
                    if matches[i]<0:continue
                    var k=1+matches[i]*WPOINT;var lambda_n=current_p[unsafe_offset=k+6];var impulse=Vec3(current_p[unsafe_offset=k+7],current_p[unsafe_offset=k+8],current_p[unsafe_offset=k+9])
                    if not isfinite(lambda_n) or lambda_n<0 or lambda_n>1e4 or not finite(impulse) or impulse.length()>mu*lambda_n+1e-12*(1+mu*lambda_n) or abs(impulse.dot(old_n))>1e-12*(1+impulse.length()):hit=False;diagnostic[unsafe_offset=15]+=1
                if ambiguous:hit=False;diagnostic[unsafe_offset=16]+=1
                if not hit:diagnostic[unsafe_offset=8]+=1
        if not capacity_ok:hit=False;diagnostic[unsafe_offset=9]+=1
        if hit:
            diagnostic[unsafe_offset=2]+=1
            for i in range(count):mapping[unsafe_offset=1+start+i]=Int32(matches[i])
        if not capacity_ok or not publish_allowed or flags!=0:continue
        var p=Int(pending_m[unsafe_offset=1]);var out=Int(pending_m[unsafe_offset=2]);var h=1+p*WP;var f=1+p*WF
        for i in range(11):pending_h[unsafe_offset=h+i]=key[i]
        pending_h[unsafe_offset=h+11]=feature;pending_h[unsafe_offset=h+12]=flags;pending_h[unsafe_offset=h+13]=UInt64(count);pending_h[unsafe_offset=h+14]=UInt64(out)
        pending_h[unsafe_offset=h+15]=revisions[unsafe_offset=1+Int(key[3])];pending_h[unsafe_offset=h+16]=revisions[unsafe_offset=1+Int(key[8])];pending_h[unsafe_offset=h+17]=UInt64(start)
        pending_f[unsafe_offset=f]=n.x;pending_f[unsafe_offset=f+1]=n.y;pending_f[unsafe_offset=f+2]=n.z
        pending_f[unsafe_offset=f+3]=basis[0].x;pending_f[unsafe_offset=f+4]=basis[0].y;pending_f[unsafe_offset=f+5]=basis[0].z
        pending_f[unsafe_offset=f+6]=basis[1].x;pending_f[unsafe_offset=f+7]=basis[1].y;pending_f[unsafe_offset=f+8]=basis[1].z
        for i in range(count):
            for j in range(6):pending_p[unsafe_offset=1+(out+i)*WPOINT+j]=anchors[i*6+j]
        pending_m[unsafe_offset=1]+=1;pending_m[unsafe_offset=2]+=UInt64(count)
    diagnostic[unsafe_offset=10]=Int64(pending_m[unsafe_offset=1]);diagnostic[unsafe_offset=11]=Int64(pending_m[unsafe_offset=2])

def warm_publish(headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],tracking: Pointer[UInt64,MutAnyOrigin],current_h: Pointer[UInt64,MutAnyOrigin],current_f: Pointer[Float64,MutAnyOrigin],current_p: Pointer[Float64,MutAnyOrigin],current_m: Pointer[UInt64,MutAnyOrigin],pending_h: Pointer[UInt64,MutAnyOrigin],pending_f: Pointer[Float64,MutAnyOrigin],pending_p: Pointer[Float64,MutAnyOrigin],pending_m: Pointer[UInt64,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin],c: Float64,s: Float64,mu: Float64):
    if summary[unsafe_offset=0]!=0:diagnostic[unsafe_offset=13]=1;return
    for p in range(Int(pending_m[unsafe_offset=1])):
        var h=1+p*WP;var start=Int(pending_h[unsafe_offset=h+17]);var out=Int(pending_h[unsafe_offset=h+14]);var count=Int(pending_h[unsafe_offset=h+13]);var reverse=headers[unsafe_offset=1+start*11+3]>headers[unsafe_offset=1+start*11+8];var sign=Float64(-1) if reverse else Float64(1)
        var g=1+start*10;var n=Vec3(geometry[unsafe_offset=g],geometry[unsafe_offset=g+1],geometry[unsafe_offset=g+2]);var basis=tangent_axes(n,c,s)
        for i in range(count):
            var lambda_n=impulses[unsafe_offset=1+start+i];var j=(basis[0]*tangent[unsafe_offset=1+(start+i)*2]+basis[1]*tangent[unsafe_offset=2+(start+i)*2])*sign
            if not isfinite(lambda_n) or lambda_n<0 or lambda_n>1e4 or not finite(j) or j.length()>mu*lambda_n+1e-12*(1+mu*lambda_n):pending_h[unsafe_offset=h+12]=UInt64.MAX;diagnostic[unsafe_offset=15]+=1
            var k=1+(out+i)*WPOINT;pending_p[unsafe_offset=k+6]=lambda_n;pending_p[unsafe_offset=k+7]=j.x;pending_p[unsafe_offset=k+8]=j.y;pending_p[unsafe_offset=k+9]=j.z
    for i in range(16*WP):current_h[unsafe_offset=1+i]=pending_h[unsafe_offset=1+i]
    for i in range(16*WF):current_f[unsafe_offset=1+i]=pending_f[unsafe_offset=1+i]
    for i in range(64*WPOINT):current_p[unsafe_offset=1+i]=pending_p[unsafe_offset=1+i]
    for i in range(1,WMETA-1):current_m[unsafe_offset=i]=pending_m[unsafe_offset=i]
    tracking[unsafe_offset=3]=tracking[unsafe_offset=2];tracking[unsafe_offset=4]=tracking[unsafe_offset=1];tracking[unsafe_offset=5]=1;diagnostic[unsafe_offset=12]=1

def warm_clear_meta(meta: Pointer[UInt64,MutAnyOrigin]):
    for i in range(1,WMETA-1):meta[unsafe_offset=i]=0
