"""Separate certified coherent normal patch correction; frozen temporal budgets."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .core import BodyState,component,finite
from .kernels import WORDS,CAPACITY,load,store
from .response_kernels import body_profile,inv_inertia,kinetic
from .shape_kernels import SHAPES,BOX,mi,vi,write_pair
from .box_response_math import normal_block

@fieldwise_init
struct FloorTOI(ImplicitlyCopyable,Movable):
    var time: Float64
    var found: Bool
    var valid: Bool

def floor_toi(gap: Float64,v: Float64,a: Float64,limit: Float64) -> FloorTOI:
    var best=limit+1
    if a==0:
        if v<0:best=-gap/v
    else:
        var disc=v*v-2*a*gap
        if disc>=0:
            var root=sqrt(disc);var q=-.5*(v+(root if v>=0 else -root))
            if q!=0:
                var t0=q/(.5*a);var t1=gap/q
                if t0>=0 and t0<=limit and v+a*t0<0:best=t0
                if t1>=0 and t1<=limit and v+a*t1<0:best=min(best,t1)
            elif gap==0 and v<0:best=0
    if best<0 or best>limit:return FloorTOI(0,False,True)
    var error=abs(gap+v*best+.5*a*best*best)
    return FloorTOI(best,True,isfinite(best) and error<=1e-9 and v+a*best<0)

def corner(b: BodyState,half: Vec3,i: Int) -> Vec3:
    return b.position+b.orientation.rotate(Vec3(-half.x if i<2 else half.x,-half.y,-half.z if i%2==0 else half.z))
def point_speed(b: BodyState,p: Vec3) -> Float64:
    return (b.linear+b.angular.cross(p-b.position)).y

def point_order(code: Int) -> Array[Int,4]:
    var remaining: Array[Int,4]=[0,1,2,3];var result=Array[Int,4](fill=0);var factor: Array[Int,4]=[6,2,1,1];var rank=code
    for i in range(4):
        var j=rank//factor[i];rank%=factor[i];result[i]=remaining[j]
        for k in range(j,3-i):remaining[k]=remaining[k+1]
    return result^

def certified_face(b: BodyState,half: Vec3,floor_y: Float64) -> Bool:
    var low=Float64(1e30);var high=Float64(-1e30)
    for i in range(4):
        var gap=corner(b,half,i).y-floor_y
        if not isfinite(gap) or gap>1e-9 or gap < -1e-5-1e-9:return False
        low=min(low,gap);high=max(high,gap)
    return high-low<=1e-9

def correct(mut b: BodyState,half: Vec3,floor_y: Float64,mut lambda_n: Array[Float64,4],target: Float64,sweeps: Int,summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],order: Int32):
    if summary[unsafe_offset=0]!=0:return
    if not certified_face(b,half,floor_y):summary[unsafe_offset=0]=310;return
    var before=kinetic(b);var permutation=point_order(Int(order));var arms=Array[Vec3,4](fill=Vec3(0,0,0));var gram=Array[Float64,16](fill=0);var tol=Float64(1e-9)
    for i in range(4):
        var p=corner(b,half,permutation[i]);p.y=(p.y+floor_y)*.5;arms[i]=(p-b.position).cross(Vec3(0,1,0))
        var speed=abs(point_speed(b,p));tol=max(tol,1e-9*(1+speed));stats[unsafe_offset=18]=max(stats[unsafe_offset=18],speed)
    for i in range(4):
        for j in range(4):gram[i*4+j]=1/b.mass+arms[i].dot(inv_inertia(b,arms[j]))
    for _ in range(sweeps):
        summary[unsafe_offset=3]+=1
        var q=Array[Float64,4](fill=0)
        for i in range(4):
            var p=corner(b,half,permutation[i]);p.y=(p.y+floor_y)*.5;q[i]=point_speed(b,p)-target
            for j in range(4):q[i]-=gram[i*4+j]*lambda_n[permutation[j]]
        var solution=normal_block(gram,q,4,tol)
        if not solution.valid:summary[unsafe_offset=0]=308;return
        var impulse=Float64(0);var torque=Vec3(0,0,0)
        # Compute the complete patch delta at the frozen pose, then apply its
        # net linear and angular impulse. No special symmetric solution or clamp.
        for i in range(4):
            var delta=solution.impulse[i]-lambda_n[permutation[i]];impulse+=delta;torque=torque+arms[i]*delta;lambda_n[permutation[i]]=solution.impulse[i]
        b.linear.y+=impulse/b.mass;b.angular=b.angular+inv_inertia(b,torque);stats[unsafe_offset=6]+=impulse
    stats[unsafe_offset=7]=max(stats[unsafe_offset=7],kinetic(b)-before)
    if kinetic(b)>before+1e-9*(1+before):summary[unsafe_offset=0]=309

def inspect(b: BodyState,half: Vec3,floor_y: Float64,target: Float64,lambda_n: Array[Float64,4],stats: Pointer[Float64,MutAnyOrigin]):
    var residual=Float64(0);var depth=Float64(0)
    for i in range(4):
        var p=corner(b,half,i);var gap=p.y-floor_y;p.y=(p.y+floor_y)*.5
        var v=point_speed(b,p)-target
        residual=max(residual,abs(v) if lambda_n[i]>0 else max(0.0,-v));depth=max(depth,max(0.0,-gap))
        stats[unsafe_offset=20+i]=gap;stats[unsafe_offset=24+i]=v
    stats[unsafe_offset=2]=max(stats[unsafe_offset=2],depth);stats[unsafe_offset=3]=residual
    stats[unsafe_offset=4]=max(stats[unsafe_offset=4],component(b.angular))
    var q=b.orientation;stats[unsafe_offset=5]=max(stats[unsafe_offset=5],2*sqrt(q.x*q.x+q.y*q.y+q.z*q.z)/abs(q.w))
    stats[unsafe_offset=30]=target

def shape_identity(values: Pointer[Float64,MutAnyOrigin],s: Int) -> Bool:
    return vi(values,1,s)==0 and vi(values,2,s)==0 and vi(values,3,s)==0 and vi(values,7,s)==0 and vi(values,8,s)==0 and vi(values,9,s)==0 and vi(values,10,s)==1

def temporal_patch_floor(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],generations: Pointer[UInt64,MutAnyOrigin],namespace: Pointer[UInt64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],group: Pointer[Float64,MutAnyOrigin],episode: Pointer[UInt64,MutAnyOrigin],pending: Pointer[UInt64,MutAnyOrigin],last: Pointer[Float64,MutAnyOrigin],pending_last: Pointer[Float64,MutAnyOrigin],dt: Float64,gx: Float64,gy: Float64,gz: Float64,e: Float64,mu: Float64,order: Int32):
    for i in range(6):summary[unsafe_offset=i]=0
    summary[unsafe_offset=4]=-1;summary[unsafe_offset=5]=-1
    for i in range(1,31):stats[unsafe_offset=i]=0
    for i in range(1,5):group[unsafe_offset=i]=0
    for i in range(WORDS):candidate[unsafe_offset=i]=current[unsafe_offset=i]
    for i in range(1,15):pending[unsafe_offset=i]=0
    var gravity=Vec3(gx,gy,gz)
    if dt!=1.0/30 or not finite(gravity) or not isfinite(e) or e<0 or e>1 or mu!=0 or order<0 or order>=24:summary[unsafe_offset=0]=300;return
    var dynamic=-1;var floor=-1;var nd=0;var nf=0
    for i in range(CAPACITY):
        if active[unsafe_offset=i+1]!=1:continue
        var state=load(current,i)
        if not body_profile(state):summary[unsafe_offset=0]=302;return
        if state.mass>0:dynamic=i;nd+=1
        else:floor=i;nf+=1
    if nd!=1 or nf>1:summary[unsafe_offset=0]=301;return
    summary[unsafe_offset=4]=Int32(dynamic);summary[unsafe_offset=5]=Int32(floor)
    var ds=-1;var fs=-1;var shape_count=0
    for s in range(SHAPES):
        if mi(meta,0,s)!=1:continue
        shape_count+=1
        var body=Int(mi(meta,3,s))
        if mi(meta,6,s)!=BOX or body<0 or body>=CAPACITY or active[unsafe_offset=body+1]!=1 or mi(meta,4,s)!=generations[unsafe_offset=body+1] or mi(meta,5,s)!=namespace[unsafe_offset=1] or not shape_identity(values,s):summary[unsafe_offset=0]=301;return
        if body==dynamic:ds=s
        elif body==floor:fs=s
        else:summary[unsafe_offset=0]=301;return
        for axis in range(4,7):
            if vi(values,axis,s)<.05 or vi(values,axis,s)>10:summary[unsafe_offset=0]=301;return
    if ds<0 or shape_count!=(2 if floor>=0 else 1) or (floor>=0 and fs<0):summary[unsafe_offset=0]=301;return
    var b=load(current,dynamic);var force=b.force;var torque=b.torque;var accel=gravity+force*(1/b.mass)
    var half=Vec3(vi(values,4,ds),vi(values,5,ds),vi(values,6,ds));var floor_y=Float64(0);var touching=False
    var key=Array[UInt64,11](fill=0)
    if floor>=0:
        var f=load(current,floor);var q=b.orientation;var fq=f.orientation
        if abs(q.x)>5e-11 or abs(q.y)>5e-11 or abs(q.z)>5e-11 or abs(q.w-1)>1e-10 or b.angular.length()>1e-10 or component(torque)!=0 or fq.x!=0 or fq.y!=0 or fq.z!=0 or fq.w!=1 or component(f.force)!=0 or component(f.torque)!=0:summary[unsafe_offset=0]=301;return
        floor_y=f.position.y+vi(values,5,fs)
        var gap=b.position.y-half.y-floor_y
        if gap < -1e-9:summary[unsafe_offset=0]=303;return
        # Conservative finite-floor coverage for the entire macro duration.
        var dx=abs(b.linear.x)*dt+.5*abs(accel.x)*dt*dt;var dz=abs(b.linear.z)*dt+.5*abs(accel.z)*dt*dt
        if abs(b.position.x-f.position.x)+half.x+dx>vi(values,4,fs) or abs(b.position.z-f.position.z)+half.z+dz>vi(values,6,fs):summary[unsafe_offset=0]=304;return
        var sa=min(ds,fs);var sb=max(ds,fs)
        # The complete key is constructed directly, with no stale ordinal key.
        for field in range(5):
            key[field]=mi(meta,field+1,sa);key[field+5]=mi(meta,field+1,sb)
        key[0]=UInt64(sa);key[1]=mi(meta,1,sa);key[2]=mi(meta,2,sa);key[3]=mi(meta,3,sa);key[4]=mi(meta,4,sa)
        key[5]=UInt64(sb);key[6]=mi(meta,1,sb);key[7]=mi(meta,2,sb);key[8]=mi(meta,3,sb);key[9]=mi(meta,4,sb);key[10]=namespace[unsafe_offset=1]
        var same=episode[unsafe_offset=1]==1
        for i in range(11):same=same and episode[unsafe_offset=3+i]==key[i]
        for field in range(17):same=same and last[unsafe_offset=1+field]==current[unsafe_offset=field*258+dynamic+1] and last[unsafe_offset=24+field]==current[unsafe_offset=field*258+floor+1]
        touching=same and episode[unsafe_offset=2]==1 and gap<=1e-9
        if gap<=1e-9 and b.linear.y==0:touching=True
    stats[unsafe_offset=13]=floor_y;stats[unsafe_offset=14]=b.position.y;stats[unsafe_offset=15]=accel.y
    var lambda_n=Array[Float64,4](fill=0);var last_group=False;var last_target=Float64(0)
    for interval in range(4):
        var remaining=Float64(1.0/120)
        for segment in range(6):
            if remaining<=0:break
            if floor<0:
                b.force=force;b.torque=torque
                var status=b.integrate(remaining,gravity,remaining)
                if status!=0:summary[unsafe_offset=0]=302;break
                stats[unsafe_offset=1]+=remaining;remaining=0;last_group=False;break
            var gap=Float64(1e30);var min_speed=Float64(1e30)
            for i in range(4):gap=min(gap,corner(b,half,i).y-floor_y);min_speed=min(min_speed,point_speed(b,corner(b,half,i)))
            if gap>1e-9:touching=False
            if touching and min_speed<=1e-9:
                var step=remaining
                b.linear=b.linear+accel*(step*.5)
                lambda_n=Array[Float64,4](fill=0);correct(b,half,floor_y,lambda_n,0,2,summary,stats,order)
                if summary[unsafe_offset=0]!=0:break
                b.force=Vec3(0,0,0);b.torque=Vec3(0,0,0)
                var status=b.integrate(step,Vec3(0,0,0),step)
                if status!=0:summary[unsafe_offset=0]=302;break
                b.linear=b.linear+accel*(step*.5)
                lambda_n=Array[Float64,4](fill=0);correct(b,half,floor_y,lambda_n,0,2,summary,stats,order)
                last_group=True;last_target=0;stats[unsafe_offset=1]+=step;remaining=0
                inspect(b,half,floor_y,last_target,lambda_n,stats)
                if stats[unsafe_offset=2]>1e-5+1e-9:summary[unsafe_offset=0]=307
                break
            # Analytic impact certificate requires the actual segment-entry
            # physical state to have fixed orientation; never hide induced spin.
            if component(b.angular)>1e-12:summary[unsafe_offset=0]=306;break
            var event=floor_toi(gap,b.linear.y,accel.y,remaining)
            if not event.valid:summary[unsafe_offset=0]=305;break
            var step=event.time if event.found else remaining
            if step>0:
                b.force=force;b.torque=torque
                var status=b.integrate(step,gravity,step)
                if status!=0:summary[unsafe_offset=0]=302;break
                stats[unsafe_offset=1]+=step;remaining-=step
            if not event.found:last_group=False;break
            summary[unsafe_offset=2]+=1
            if summary[unsafe_offset=2]>4:summary[unsafe_offset=0]=305;break
            var actual_gap=b.position.y-half.y-floor_y
            stats[unsafe_offset=12]=max(stats[unsafe_offset=12],abs(actual_gap));stats[unsafe_offset=9]=b.linear.y;stats[unsafe_offset=11]=stats[unsafe_offset=1]
            if abs(actual_gap)>1e-9:summary[unsafe_offset=0]=305;break
            var target=-e*b.linear.y if b.linear.y<-.2 else 0.0
            lambda_n=Array[Float64,4](fill=0);correct(b,half,floor_y,lambda_n,target,2,summary,stats,order)
            stats[unsafe_offset=10]=b.linear.y;stats[unsafe_offset=17]=component(b.angular)
            inspect(b,half,floor_y,target,lambda_n,stats)
            touching=target==0;last_group=True;last_target=target
            # Physical incoming/outgoing restitution and symmetry are strict
            # gates before another event segment can be certified.
            if stats[unsafe_offset=3]>1e-9*(1+abs(stats[unsafe_offset=9])):summary[unsafe_offset=0]=308;break
            if component(b.angular)>1e-10:summary[unsafe_offset=0]=306;break
        summary[unsafe_offset=1]=Int32(interval+1);stats[unsafe_offset=28]=Float64(interval+1)
        if summary[unsafe_offset=0]!=0:break
        if remaining>0:summary[unsafe_offset=0]=305;break
    if floor>=0 and last_group and summary[unsafe_offset=0]==0:
        # Retain the final end group's pressure. Negative deltas may undo its
        # excess; accumulated pressure remains nonnegative. No group reset.
        correct(b,half,floor_y,lambda_n,last_target,4,summary,stats,order)
        inspect(b,half,floor_y,last_target,lambda_n,stats)
        if stats[unsafe_offset=3]>1e-9*(1+abs(stats[unsafe_offset=18])):summary[unsafe_offset=0]=308
        if stats[unsafe_offset=2]>1e-5+1e-9:summary[unsafe_offset=0]=307
    if floor>=0 and (b.angular.length()>1e-4 or stats[unsafe_offset=5]>1e-5):summary[unsafe_offset=0]=306
    if not body_profile(b):summary[unsafe_offset=0]=302
    for i in range(4):group[unsafe_offset=1+i]=lambda_n[i]
    b.force=force;b.torque=torque;store(candidate,dynamic,b)
    if summary[unsafe_offset=0]!=0:return
    b.force=Vec3(0,0,0);b.torque=Vec3(0,0,0);store(candidate,dynamic,b)
    pending[unsafe_offset=1]=1;pending[unsafe_offset=2]=UInt64(1 if floor>=0 and b.position.y-half.y-floor_y<=1e-9 and b.linear.y<=1e-9 else 0)
    for i in range(11):pending[unsafe_offset=3+i]=key[i]
    for field in range(23):
        pending_last[unsafe_offset=1+field]=candidate[unsafe_offset=field*258+dynamic+1]
        pending_last[unsafe_offset=24+field]=candidate[unsafe_offset=field*258+floor+1] if floor>=0 else 0

def commit_temporal(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],episode: Pointer[UInt64,MutAnyOrigin],pending: Pointer[UInt64,MutAnyOrigin],last: Pointer[Float64,MutAnyOrigin],pending_last: Pointer[Float64,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    for i in range(WORDS):current[unsafe_offset=i]=candidate[unsafe_offset=i]
    for i in range(1,15):episode[unsafe_offset=i]=pending[unsafe_offset=i]
    for i in range(1,47):last[unsafe_offset=i]=pending_last[unsafe_offset=i]
