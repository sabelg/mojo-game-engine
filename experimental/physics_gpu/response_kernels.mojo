"""G04a serial GPU projected normal impulses and split COM projection.

No atomics, shared-body races, friction or cross-call impulse reuse.
"""
from std.memory import Pointer
from std.math import isfinite,sqrt
from max.gpu import block_idx,block_dim,thread_idx
from mojo_game.math3d import Vec3
from .core import BodyState,finite,component,inverse,momentum
from .kernels import CAPACITY,STRIDE,FIELDS,load,store
from .shape_kernels import SHAPES,BOUNDS_FIELDS,SPHERE,BOX,mi,vi

comptime FULL=Int32(50)
comptime CONFIG=Int32(51)
comptime PROFILE=Int32(52)
comptime KEY=Int32(53)
comptime CONTACT=Int32(54)
comptime VELOCITY=Int32(55)
comptime ENERGY=Int32(56)
comptime DEPTH=Int32(57)
comptime POSITION=Int32(58)
comptime SHIFT=Int32(59)
comptime POST=Int32(60)
comptime NUMERIC=Int32(61)
comptime SLOP=Float64(1e-5)
comptime POS_TOL=Float64(1e-9)

def inv_mass(b: BodyState) -> Float64:
    return 0.0 if b.mass==0 else 1/b.mass
def inv_inertia(b: BodyState,v: Vec3) -> Vec3:
    return Vec3(0,0,0) if b.mass==0 else inverse(b.orientation,b.inertia,v)
def kinetic(b: BodyState) -> Float64:
    if b.mass==0:return 0
    return .5*(b.mass*b.linear.dot(b.linear)+b.angular.dot(momentum(b.orientation,b.inertia,b.angular)))
def body_profile(b: BodyState) -> Bool:
    if not b.valid() or component(b.position)>1000 or component(b.linear)>20 or component(b.angular)>10:return False
    var q=b.orientation;var norm=q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w
    if abs(norm-1)>1e-10:return False
    if b.mass==0:return True
    return b.mass>=.1 and b.mass<=100 and min(b.inertia.x,min(b.inertia.y,b.inertia.z))>=1e-4 and component(b.inertia)<=1000
def normal(g: Pointer[Float64,MutAnyOrigin],i: Int) -> Vec3:
    var p=1+i*10;return Vec3(g[unsafe_offset=p],g[unsafe_offset=p+1],g[unsafe_offset=p+2])
def point(g: Pointer[Float64,MutAnyOrigin],i: Int) -> Vec3:
    var p=1+i*10
    return Vec3(g[unsafe_offset=p+4]*.5+g[unsafe_offset=p+7]*.5,g[unsafe_offset=p+5]*.5+g[unsafe_offset=p+8]*.5,g[unsafe_offset=p+6]*.5+g[unsafe_offset=p+9]*.5)
def normal_speed(a: BodyState,b: BodyState,p: Vec3,n: Vec3) -> Float64:
    return (b.linear+b.angular.cross(p-b.position)-a.linear-a.angular.cross(p-a.position)).dot(n)
def apply_normal(mut a: BodyState,mut b: BodyState,p: Vec3,n: Vec3,impulse: Float64):
    var j=n*impulse
    if a.mass>0:
        a.linear=a.linear-j*inv_mass(a);a.angular=a.angular-inv_inertia(a,(p-a.position).cross(j))
    if b.mass>0:
        b.linear=b.linear+j*inv_mass(b);b.angular=b.angular+inv_inertia(b,(p-b.position).cross(j))

def setup_response(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],gens: Pointer[UInt64,MutAnyOrigin],namespace: Pointer[UInt64,MutAnyOrigin],
                   meta: Pointer[UInt64,MutAnyOrigin],descriptors: Pointer[Float64,MutAnyOrigin],bounds: Pointer[Float64,MutAnyOrigin],fresh: Pointer[Float64,MutAnyOrigin],fresh_status: Pointer[Int32,MutAnyOrigin],
                   headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],raw_geometry: Pointer[Float64,MutAnyOrigin],
                   impulses: Pointer[Float64,MutAnyOrigin],position_impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],effective: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],
                   summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],count: Int32,capacity: Int32,dt: Float64,e: Float64,velocity_iterations: Int32,position_iterations: Int32):
    for i in range(5):summary[unsafe_offset=i]=0
    for i in range(6):stats[unsafe_offset=i]=0
    if count<0 or count>capacity:summary[unsafe_offset=0]=FULL;return
    if not isfinite(dt) or dt<1.0/240 or dt>1.0/30 or not isfinite(e) or e<0 or e>1 or velocity_iterations<1 or velocity_iterations>64 or position_iterations<1 or position_iterations>64:
        summary[unsafe_offset=0]=CONFIG;return
    summary[unsafe_offset=3]=count
    for i in range(CAPACITY):
        touched[unsafe_offset=i+1]=0
        for f in range(FIELDS):candidate[unsafe_offset=f*STRIDE+i+1]=current[unsafe_offset=f*STRIDE+i+1]
        if active[unsafe_offset=i+1]==1 and not body_profile(load(current,i)):summary[unsafe_offset=0]=PROFILE;return
    for s in range(SHAPES):
        if mi(meta,0,s)!=1:continue
        var kind=mi(meta,6,s)
        for f in range(1,4):
            if abs(vi(descriptors,f,s))>10:summary[unsafe_offset=0]=PROFILE;return
        if kind==SPHERE:
            if vi(descriptors,0,s)<.05 or vi(descriptors,0,s)>10:summary[unsafe_offset=0]=PROFILE;return
        elif kind==BOX:
            for f in range(4,7):
                if vi(descriptors,f,s)<.05 or vi(descriptors,f,s)>10:summary[unsafe_offset=0]=PROFILE;return
        else:summary[unsafe_offset=0]=PROFILE;return
    var speed_scale=Float64(1)
    for i in range(Int(count)):
        var h=1+i*11;var sa=headers[unsafe_offset=h];var sb=headers[unsafe_offset=h+5]
        var ia=headers[unsafe_offset=h+3];var ib=headers[unsafe_offset=h+8]
        if sa>=UInt64(SHAPES) or sb>=UInt64(SHAPES) or sa>=sb or ia>=UInt64(CAPACITY) or ib>=UInt64(CAPACITY) or ia==ib or headers[unsafe_offset=h+10]!=namespace[unsafe_offset=1]:
            summary[unsafe_offset=0]=KEY;return
        var a_slot=Int(sa);var b_slot=Int(sb)
        if mi(meta,0,a_slot)!=1 or mi(meta,0,b_slot)!=1 or mi(meta,1,a_slot)!=headers[unsafe_offset=h+1] or mi(meta,1,b_slot)!=headers[unsafe_offset=h+6] or mi(meta,2,a_slot)!=headers[unsafe_offset=h+2] or mi(meta,2,b_slot)!=headers[unsafe_offset=h+7] or mi(meta,3,a_slot)!=ia or mi(meta,3,b_slot)!=ib or mi(meta,4,a_slot)!=headers[unsafe_offset=h+4] or mi(meta,4,b_slot)!=headers[unsafe_offset=h+9] or mi(meta,5,a_slot)!=namespace[unsafe_offset=1] or mi(meta,5,b_slot)!=namespace[unsafe_offset=1] or active[unsafe_offset=Int(ia)+1]!=1 or active[unsafe_offset=Int(ib)+1]!=1 or gens[unsafe_offset=Int(ia)+1]!=headers[unsafe_offset=h+4] or gens[unsafe_offset=Int(ib)+1]!=headers[unsafe_offset=h+9]:
            summary[unsafe_offset=0]=KEY;return
        for which in range(2):
            var shape=a_slot if which==0 else b_slot
            if fresh_status[unsafe_offset=shape+1]!=0:summary[unsafe_offset=0]=KEY;return
            for f in range(BOUNDS_FIELDS):
                if bounds[unsafe_offset=1+shape*BOUNDS_FIELDS+f]!=fresh[unsafe_offset=1+shape*BOUNDS_FIELDS+f]:summary[unsafe_offset=0]=KEY;return
        var raw_pair=a_slot*(2*SHAPES-a_slot-1)//2+b_slot-a_slot-1
        for f in range(10):
            var value=geometry[unsafe_offset=1+i*10+f]
            if not isfinite(value) or value!=raw_geometry[unsafe_offset=1+raw_pair*10+f]:summary[unsafe_offset=0]=CONTACT;return
        var n=normal(geometry,i);var p=point(geometry,i)
        if abs(n.dot(n)-1)>1e-12 or geometry[unsafe_offset=1+i*10+3]>0:summary[unsafe_offset=0]=CONTACT;return
        var a=load(current,Int(ia));var b=load(current,Int(ib))
        impulses[unsafe_offset=i+1]=0;position_impulses[unsafe_offset=i+1]=0;targets[unsafe_offset=i+1]=0;effective[unsafe_offset=i+1]=0
        if a.mass==0 and b.mass==0:summary[unsafe_offset=4]+=1;continue
        if -geometry[unsafe_offset=1+i*10+3]>.25:summary[unsafe_offset=0]=DEPTH;return
        var ra=(p-a.position).cross(n);var rb=(p-b.position).cross(n)
        var k=inv_mass(a)+inv_mass(b)+ra.dot(inv_inertia(a,ra))+rb.dot(inv_inertia(b,rb))
        var initial=normal_speed(a,b,p,n)
        if not isfinite(k) or k<=0 or not isfinite(initial):summary[unsafe_offset=0]=NUMERIC;return
        effective[unsafe_offset=i+1]=k;targets[unsafe_offset=i+1]=-e*initial if initial<-.2 else 0
        speed_scale=max(speed_scale,1+abs(initial));touched[unsafe_offset=Int(ia)+1]=1;touched[unsafe_offset=Int(ib)+1]=1
    var energy=Float64(0)
    for i in range(CAPACITY):
        if touched[unsafe_offset=i+1]:energy+=kinetic(load(current,i))
    stats[unsafe_offset=0]=energy;stats[unsafe_offset=5]=1e-9*speed_scale

def solve_velocities(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],effective: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],count: Int32,iterations: Int32):
    if summary[unsafe_offset=0]!=0:return
    var converged=Int(count)==0
    for sweep in range(Int(iterations)):
        if converged:break
        for i in range(Int(count)):
            var k=effective[unsafe_offset=i+1]
            if k==0:continue
            var h=1+i*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8])
            var a=load(candidate,ia);var b=load(candidate,ib);var n=normal(geometry,i);var p=point(geometry,i)
            var old=impulses[unsafe_offset=i+1];var next=max(0.0,old+(targets[unsafe_offset=i+1]-normal_speed(a,b,p,n))/k)
            if not isfinite(next) or next>1e4:summary[unsafe_offset=0]=NUMERIC;return
            apply_normal(a,b,p,n,next-old)
            if not body_profile(a) or not body_profile(b):summary[unsafe_offset=0]=PROFILE;return
            impulses[unsafe_offset=i+1]=next;store(candidate,ia,a);store(candidate,ib,b)
        var residual=Float64(0)
        for i in range(Int(count)):
            if effective[unsafe_offset=i+1]==0:continue
            var h=1+i*11;var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]))
            var error=normal_speed(a,b,point(geometry,i),normal(geometry,i))-targets[unsafe_offset=i+1]
            residual=max(residual,abs(error) if impulses[unsafe_offset=i+1]>0 else max(0.0,-error))
        summary[unsafe_offset=1]=Int32(sweep+1);stats[unsafe_offset=2]=residual;converged=residual<=stats[unsafe_offset=5]
    if not converged:summary[unsafe_offset=0]=VELOCITY;return
    var energy=Float64(0)
    for i in range(CAPACITY):
        if touched[unsafe_offset=i+1]:energy+=kinetic(load(candidate,i))
    stats[unsafe_offset=1]=energy
    if not isfinite(energy) or energy>stats[unsafe_offset=0]+1e-9*(1+stats[unsafe_offset=0]):summary[unsafe_offset=0]=ENERGY

def project_positions(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],effective: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],count: Int32,iterations: Int32):
    if summary[unsafe_offset=0]!=0:return
    var converged=Int(count)==0
    for sweep in range(Int(iterations)):
        if converged:break
        for i in range(Int(count)):
            if effective[unsafe_offset=i+1]==0:continue
            var h=1+i*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8]);var a=load(candidate,ia);var b=load(candidate,ib)
            var original_a=load(current,ia);var original_b=load(current,ib);var n=normal(geometry,i)
            var separation=geometry[unsafe_offset=1+i*10+3]+n.dot((b.position-original_b.position)-(a.position-original_a.position))
            var old=impulses[unsafe_offset=i+1];var next=max(0.0,old-(separation+SLOP)/(inv_mass(a)+inv_mass(b)))
            if not isfinite(next):summary[unsafe_offset=0]=NUMERIC;return
            if a.mass>0:a.position=a.position-n*((next-old)*inv_mass(a))
            if b.mass>0:b.position=b.position+n*((next-old)*inv_mass(b))
            impulses[unsafe_offset=i+1]=next
            var shift=max((a.position-original_a.position).length(),(b.position-original_b.position).length())
            stats[unsafe_offset=4]=max(stats[unsafe_offset=4],shift)
            if shift>.25:summary[unsafe_offset=0]=SHIFT;return
            if not body_profile(a) or not body_profile(b):summary[unsafe_offset=0]=PROFILE;return
            store(candidate,ia,a);store(candidate,ib,b)
        var residual=Float64(0)
        for i in range(Int(count)):
            if effective[unsafe_offset=i+1]==0:continue
            var h=1+i*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8]);var a=load(candidate,ia);var b=load(candidate,ib)
            var original_a=load(current,ia);var original_b=load(current,ib)
            var error=geometry[unsafe_offset=1+i*10+3]+normal(geometry,i).dot((b.position-original_b.position)-(a.position-original_a.position))+SLOP
            residual=max(residual,abs(error) if impulses[unsafe_offset=i+1]>0 else max(0.0,-error))
        summary[unsafe_offset=2]=Int32(sweep+1);converged=residual<=POS_TOL
    if not converged:summary[unsafe_offset=0]=POSITION

def validate_response(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],post_summary: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    if post_summary[unsafe_offset=0]!=0:summary[unsafe_offset=0]=POST;return
    for i in range(Int(post_summary[unsafe_offset=2])):
        var h=1+i*11;var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]))
        if a.mass==0 and b.mass==0:continue
        var separation=geometry[unsafe_offset=1+i*10+3];stats[unsafe_offset=3]=max(stats[unsafe_offset=3],max(0.0,-separation))
        if separation < -SLOP-POS_TOL or normal_speed(a,b,point(geometry,i),normal(geometry,i)) < -stats[unsafe_offset=5]:summary[unsafe_offset=0]=POST;return

def commit_response(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY or active[unsafe_offset=i+1]!=1 or summary[unsafe_offset=0]!=0:return
    for f in range(FIELDS):current[unsafe_offset=f*STRIDE+i+1]=candidate[unsafe_offset=f*STRIDE+i+1]
