"""Isolated serial box patch response, private projection and body transaction."""
from .packed_operator_codec import encode_operator_table,decode_operator_local
from std.collections import Array
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game import Vec3
from .core import BodyState,finite
from .kernels import CAPACITY,STRIDE,FIELDS,load,store
from .shape_kernels import SHAPES,PAIRS,BOX,mi,vi,write_pair
from .box_box_kernels import Patch,EPS,box
from .box_response_math import reduce_patch,mask_operators,cached_normal_block
from .response_kernels import inv_mass,inv_inertia,kinetic,body_profile,normal,point,normal_speed,apply_normal,SLOP,POS_TOL
from .friction_kernels import tangent_axes,point_velocity,tangent_metric,disk_min,apply_tangent

comptime BR_LIMIT=Int32(110)
comptime BR_CONFIG=Int32(111)
comptime BR_GEOMETRY=Int32(112)
comptime BR_BLOCK=Int32(113)
comptime BR_VELOCITY=Int32(114)
comptime BR_POSITION=Int32(115)
comptime BR_POST=Int32(116)
comptime BR_PROFILE=Int32(117)
comptime BR_ENERGY=Int32(118)
comptime BR_TOPOLOGY=Int32(119)
comptime BR_CONE=Int32(120)

def raw_normal(values: Pointer[Float64,MutAnyOrigin],p: Int) -> Vec3:
    var k=1+p*7;return Vec3(values[unsafe_offset=k+3],values[unsafe_offset=k+4],values[unsafe_offset=k+5])
def raw_origin(values: Pointer[Float64,MutAnyOrigin],p: Int) -> Vec3:
    var k=1+p*7;return Vec3(values[unsafe_offset=k],values[unsafe_offset=k+1],values[unsafe_offset=k+2])
def metric(a: BodyState,b: BodyState,p: Vec3,q: Vec3,n: Vec3) -> Float64:
    var ai=(p-a.position).cross(n);var aj=(q-a.position).cross(n);var bi=(p-b.position).cross(n);var bj=(q-b.position).cross(n)
    return inv_mass(a)+inv_mass(b)+ai.dot(inv_inertia(a,aj))+bi.dot(inv_inertia(b,bj))

def begin_box_response(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],
    meta: Pointer[UInt64,MutAnyOrigin],descriptors: Pointer[Float64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin],flags: Pointer[Int32,MutAnyOrigin],errors: Pointer[Int32,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],
    initial: Pointer[Int32,MutAnyOrigin],position_impulses: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],dt: Float64,e: Float64,mu: Float64,vi_count: Int32,pi_count: Int32,velocity_budget: Int32):
    for i in range(6):summary[unsafe_offset=i]=0
    for i in range(9):stats[unsafe_offset=i]=0
    if (velocity_budget!=64 and velocity_budget!=96) or not isfinite(dt) or dt<1.0/240 or dt>1.0/30 or not isfinite(e) or e<0 or e>1 or not isfinite(mu) or mu<0 or mu>2 or vi_count<1 or vi_count>velocity_budget or pi_count<1 or pi_count>64:
        summary[unsafe_offset=0]=BR_CONFIG;return
    for i in range(CAPACITY):
        for f in range(FIELDS):candidate[unsafe_offset=f*STRIDE+i+1]=current[unsafe_offset=f*STRIDE+i+1]
        if active[unsafe_offset=i+1]==1 and not body_profile(load(current,i)):summary[unsafe_offset=0]=BR_PROFILE;return
    for s in range(SHAPES):
        if statuses[unsafe_offset=s+1]!=0:summary[unsafe_offset=0]=BR_GEOMETRY;return
        if mi(meta,0,s)!=1:continue
        if mi(meta,6,s)!=BOX:summary[unsafe_offset=0]=BR_PROFILE;return
        for f in range(1,4):
            if abs(vi(descriptors,f,s))>10:summary[unsafe_offset=0]=BR_PROFILE;return
        for f in range(4,7):
            if vi(descriptors,f,s)<.05 or vi(descriptors,f,s)>10:summary[unsafe_offset=0]=BR_PROFILE;return
    var pairs=0
    for a in range(SHAPES):
        for b in range(a+1,SHAPES):
            var p=a*(2*SHAPES-a-1)//2+b-a-1;initial[unsafe_offset=p+1]=0;position_impulses[unsafe_offset=p+1]=0
            if errors[unsafe_offset=p+1]!=0:summary[unsafe_offset=0]=BR_GEOMETRY;return
            if flags[unsafe_offset=p+1]==0:continue
            var ia=Int(mi(meta,3,a));var ib=Int(mi(meta,3,b));var aa=load(current,ia);var bb=load(current,ib)
            if ia==ib:continue
            if aa.mass==0 and bb.mass==0:summary[unsafe_offset=5]+=1;continue
            if -values[unsafe_offset=1+p*7+6]>.25:summary[unsafe_offset=0]=BR_POSITION;return
            initial[unsafe_offset=p+1]=1;pairs+=1
    if pairs>16:summary[unsafe_offset=0]=BR_LIMIT

def project_box_response(entry: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],initial: Pointer[Int32,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],iterations: Int32):
    if summary[unsafe_offset=0]!=0:return
    var converged=False
    for sweep in range(Int(iterations)):
        for a in range(SHAPES):
            for b in range(a+1,SHAPES):
                var p=a*(2*SHAPES-a-1)//2+b-a-1
                if initial[unsafe_offset=p+1]==0:continue
                var ia=Int(mi(meta,3,a));var ib=Int(mi(meta,3,b));var aa=load(candidate,ia);var bb=load(candidate,ib);var oa=load(entry,ia);var ob=load(entry,ib);var n=raw_normal(values,p)
                var gap=values[unsafe_offset=1+p*7+6]+n.dot((bb.position-ob.position)-(aa.position-oa.position))
                var old=impulses[unsafe_offset=p+1];var next=max(0.0,old-(gap+SLOP)/(inv_mass(aa)+inv_mass(bb)));var delta=next-old
                if not isfinite(next):summary[unsafe_offset=0]=BR_POSITION;return
                if aa.mass>0:aa.position=aa.position-n*(delta*inv_mass(aa))
                if bb.mass>0:bb.position=bb.position+n*(delta*inv_mass(bb))
                impulses[unsafe_offset=p+1]=next;store(candidate,ia,aa);store(candidate,ib,bb)
                var shift=max((aa.position-oa.position).length(),(bb.position-ob.position).length());stats[unsafe_offset=4]=max(stats[unsafe_offset=4],shift)
                if shift>.25 or not body_profile(aa) or not body_profile(bb):summary[unsafe_offset=0]=BR_POSITION;return
        var residual=Float64(0)
        for a in range(SHAPES):
            for b in range(a+1,SHAPES):
                var p=a*(2*SHAPES-a-1)//2+b-a-1
                if initial[unsafe_offset=p+1]==0:continue
                var ia=Int(mi(meta,3,a));var ib=Int(mi(meta,3,b));var aa=load(candidate,ia);var bb=load(candidate,ib);var oa=load(entry,ia);var ob=load(entry,ib)
                var gap=values[unsafe_offset=1+p*7+6]+raw_normal(values,p).dot((bb.position-ob.position)-(aa.position-oa.position))+SLOP
                residual=max(residual,abs(gap) if impulses[unsafe_offset=p+1]>0 else max(0.0,-gap))
        summary[unsafe_offset=2]=Int32(sweep+1);converged=residual<=POS_TOL
        if converged:break
    if not converged:summary[unsafe_offset=0]=BR_POSITION

def pack_box_packed_response(candidate: Pointer[Float64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],bounds: Pointer[Float64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin],initial: Pointer[Int32,MutAnyOrigin],
    flags: Pointer[Int32,MutAnyOrigin],counts: Pointer[Int32,MutAnyOrigin],errors: Pointer[Int32,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],raw_points: Pointer[Float64,MutAnyOrigin],
    headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],grams: Pointer[Float64,MutAnyOrigin],operators: Pointer[Float64,MutAnyOrigin],operator_metadata: Pointer[Int32,MutAnyOrigin],mask_valid: Pointer[Int32,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],capacity: Int32,e: Float64):
    if summary[unsafe_offset=0]!=0:return
    for s in range(SHAPES):
        if statuses[unsafe_offset=s+1]!=0:summary[unsafe_offset=0]=BR_GEOMETRY;return
    for i in range(CAPACITY):touched[unsafe_offset=i+1]=0
    var pairs=0;var output=0;var normal_tolerance=Float64(1e-9);var tangent_tolerance=Float64(1e-9)
    for a in range(SHAPES):
        for b in range(a+1,SHAPES):
            var p=a*(2*SHAPES-a-1)//2+b-a-1
            if errors[unsafe_offset=p+1]!=0:summary[unsafe_offset=0]=BR_GEOMETRY;return
            if flags[unsafe_offset=p+1]==0:continue
            var ia=Int(mi(meta,3,a));var ib=Int(mi(meta,3,b));var aa=load(candidate,ia);var bb=load(candidate,ib)
            if ia==ib or (aa.mass==0 and bb.mass==0):continue
            if initial[unsafe_offset=p+1]!=1:summary[unsafe_offset=0]=BR_TOPOLOGY;return
            var gap=values[unsafe_offset=1+p*7+6]
            if gap < -SLOP-POS_TOL:summary[unsafe_offset=0]=BR_POST;return
            var n=raw_normal(values,p);var origin=raw_origin(values,p);var patch=Patch();patch.count=counts[unsafe_offset=p+1]
            if patch.count<1 or patch.count>9 or abs(n.dot(n)-1)>1e-12:summary[unsafe_offset=0]=BR_GEOMETRY;return
            for i in range(Int(patch.count)):
                var k=1+(p*9+i)*7
                patch.a[i]=Vec3(raw_points[unsafe_offset=k],raw_points[unsafe_offset=k+1],raw_points[unsafe_offset=k+2]);patch.b[i]=Vec3(raw_points[unsafe_offset=k+3],raw_points[unsafe_offset=k+4],raw_points[unsafe_offset=k+5]);patch.separation[i]=raw_points[unsafe_offset=k+6]
            var ba=box(bounds,a);var bc=box(bounds,b);var resolution=32*EPS*max(1.0,max(max(ba.half.x,max(ba.half.y,ba.half.z)),max(bc.half.x,max(bc.half.y,bc.half.z))))
            var reduced=reduce_patch(patch,n,resolution)
            if pairs>=16 or output+reduced.count>Int(capacity):summary[unsafe_offset=0]=BR_LIMIT;return
            spans[unsafe_offset=1+pairs*2]=Int32(output);spans[unsafe_offset=2+pairs*2]=Int32(reduced.count)
            for i in range(reduced.count):
                var index=reduced.indices[i];var wa=origin+patch.a[index];var wb=origin+patch.b[index];var contact=wa*.5+wb*.5;var g=1+(output+i)*10
                write_pair(headers,output+i,a,b,meta);geometry[unsafe_offset=g]=n.x;geometry[unsafe_offset=g+1]=n.y;geometry[unsafe_offset=g+2]=n.z;geometry[unsafe_offset=g+3]=patch.separation[index]
                geometry[unsafe_offset=g+4]=wa.x;geometry[unsafe_offset=g+5]=wa.y;geometry[unsafe_offset=g+6]=wa.z;geometry[unsafe_offset=g+7]=wb.x;geometry[unsafe_offset=g+8]=wb.y;geometry[unsafe_offset=g+9]=wb.z
                var incoming=normal_speed(aa,bb,contact,n);targets[unsafe_offset=1+output+i]=-e*incoming if incoming<-.2 else 0;impulses[unsafe_offset=1+output+i]=0
                tangent[unsafe_offset=1+(output+i)*2]=0;tangent[unsafe_offset=2+(output+i)*2]=0
                normal_tolerance=max(normal_tolerance,1e-9*(1+abs(incoming)));var velocity=point_velocity(aa,bb,contact);var vt=velocity-n*velocity.dot(n);tangent_tolerance=max(tangent_tolerance,1e-9*(1+vt.length()))
            for i in range(reduced.count):
                for j in range(reduced.count):grams[unsafe_offset=1+pairs*16+i*4+j]=metric(aa,bb,point(geometry,output+i),point(geometry,output+j),n)
            var block=Array[Float64,16](fill=0)
            for i in range(reduced.count):
                for j in range(reduced.count):block[i*4+j]=grams[unsafe_offset=1+pairs*16+i*4+j]
            var cached=mask_operators(block,reduced.count)
            for mask in range(1<<reduced.count):
                mask_valid[unsafe_offset=1+pairs*16+mask]=1 if cached.valid[mask] else 0
            encode_operator_table(cached.values,reduced.count,operators,operator_metadata,pairs)
            touched[unsafe_offset=ia+1]=1;touched[unsafe_offset=ib+1]=1;output+=reduced.count;pairs+=1
    summary[unsafe_offset=3]=Int32(pairs);summary[unsafe_offset=4]=Int32(output);stats[unsafe_offset=5]=normal_tolerance;stats[unsafe_offset=6]=tangent_tolerance
    var energy=Float64(0)
    for i in range(CAPACITY):
        if touched[unsafe_offset=i+1]:energy+=kinetic(load(candidate,i))
    stats[unsafe_offset=0]=energy

def solve_box_packed_normal(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],grams: Pointer[Float64,MutAnyOrigin],operators: Pointer[Float64,MutAnyOrigin],operator_metadata: Pointer[Int32,MutAnyOrigin],mask_valid: Pointer[Int32,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],mu: Float64,iterations: Int32):
    if summary[unsafe_offset=0]!=0:return
    var pairs=Int(summary[unsafe_offset=3]);var contacts=Int(summary[unsafe_offset=4]);var converged=pairs==0
    for sweep in range(Int(iterations)):
        if converged:break
        for patch in range(pairs):
            var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var h=1+start*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8])
            var aa=load(candidate,ia);var bb=load(candidate,ib);var n=normal(geometry,start);var k=Array[Float64,16](fill=0);var q=Array[Float64,4](fill=0)
            for i in range(count):
                q[i]=normal_speed(aa,bb,point(geometry,start+i),n)-targets[unsafe_offset=1+start+i]
                for j in range(count):
                    k[i*4+j]=grams[unsafe_offset=1+patch*16+i*4+j];q[i]-=k[i*4+j]*impulses[unsafe_offset=1+start+j]
            var cached=Array[Float64,256](fill=0);var valid=Array[Bool,16](fill=False)
            for mask in range(1<<count):
                valid[mask]=mask_valid[unsafe_offset=1+patch*16+mask]!=0
            decode_operator_local(operators,operator_metadata,patch,count,cached)
            var result=cached_normal_block(k,q,cached,valid,count,stats[unsafe_offset=5])
            if not result.valid:summary[unsafe_offset=0]=BR_BLOCK;return
            for i in range(count):
                var old=impulses[unsafe_offset=1+start+i];apply_normal(aa,bb,point(geometry,start+i),n,result.impulse[i]-old);impulses[unsafe_offset=1+start+i]=result.impulse[i]
            if mu>0:
                for i in range(count):
                    var index=start+i;var p=point(geometry,index);var basis=tangent_axes(n,1,0);var t=basis[0];var u=basis[1];var mass=tangent_metric(aa,bb,p,t,u)
                    if not finite(mass) or mass.x<=0 or mass.z<=0 or mass.x*mass.z-mass.y*mass.y<=0:summary[unsafe_offset=0]=BR_CONE;return
                    var old_x=tangent[unsafe_offset=1+index*2];var old_y=tangent[unsafe_offset=2+index*2];var v=point_velocity(aa,bb,p)
                    var free=Vec3(v.dot(t)-mass.x*old_x-mass.y*old_y,v.dot(u)-mass.y*old_x-mass.z*old_y,0)
                    var next=disk_min(mass,free,mu*impulses[unsafe_offset=index+1])
                    if not finite(next):summary[unsafe_offset=0]=BR_CONE;return
                    apply_tangent(aa,bb,p,t*(next.x-old_x)+u*(next.y-old_y));tangent[unsafe_offset=1+index*2]=next.x;tangent[unsafe_offset=2+index*2]=next.y
            if not body_profile(aa) or not body_profile(bb):summary[unsafe_offset=0]=BR_PROFILE;return
            store(candidate,ia,aa);store(candidate,ib,bb)
        var residual=Float64(0);var friction_residual=Float64(0);var excess=Float64(0)
        for i in range(contacts):
            var h=1+i*11;var aa=load(candidate,Int(headers[unsafe_offset=h+3]));var bb=load(candidate,Int(headers[unsafe_offset=h+8]));var n=normal(geometry,i);var p=point(geometry,i)
            var error=normal_speed(aa,bb,p,n)-targets[unsafe_offset=i+1];residual=max(residual,abs(error) if impulses[unsafe_offset=i+1]>0 else max(0.0,-error))
            if mu>0:
                var basis=tangent_axes(n,1,0);var t=basis[0];var u=basis[1];var mass=tangent_metric(aa,bb,p,t,u);var x=tangent[unsafe_offset=1+i*2];var y=tangent[unsafe_offset=2+i*2];var v=point_velocity(aa,bb,p)
                var free=Vec3(v.dot(t)-mass.x*x-mass.y*y,v.dot(u)-mass.y*x-mass.z*y,0);var radius=mu*impulses[unsafe_offset=i+1];var optimum=disk_min(mass,free,radius)
                var dx=x-optimum.x;var dy=y-optimum.y;friction_residual=max(friction_residual,sqrt((mass.x*dx+mass.y*dy)**2+(mass.y*dx+mass.z*dy)**2));excess=max(excess,max(0.0,sqrt(x*x+y*y)-radius))
                if sqrt(x*x+y*y)>radius+1e-12*(1+radius):summary[unsafe_offset=0]=BR_CONE;return
        history[unsafe_offset=1+sweep*2]=residual;history[unsafe_offset=2+sweep*2]=friction_residual
        summary[unsafe_offset=1]=Int32(sweep+1);stats[unsafe_offset=2]=residual;stats[unsafe_offset=7]=friction_residual;stats[unsafe_offset=8]=excess
        converged=residual<=stats[unsafe_offset=5] and friction_residual<=stats[unsafe_offset=6]
    if not converged:summary[unsafe_offset=0]=BR_VELOCITY;return
    var energy=Float64(0)
    for i in range(CAPACITY):
        if touched[unsafe_offset=i+1]:energy+=kinetic(load(candidate,i))
    stats[unsafe_offset=1]=energy
    if not isfinite(energy) or energy>stats[unsafe_offset=0]+1e-9*(1+stats[unsafe_offset=0]):summary[unsafe_offset=0]=BR_ENERGY

def validate_box_response(candidate: Pointer[Float64,MutAnyOrigin],projected: Pointer[Float64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],flags: Pointer[Int32,MutAnyOrigin],counts: Pointer[Int32,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],raw_points: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],e: Float64):
    if summary[unsafe_offset=0]!=0:return
    for a in range(SHAPES):
        for b in range(a+1,SHAPES):
            var p=a*(2*SHAPES-a-1)//2+b-a-1
            if flags[unsafe_offset=p+1]==0:continue
            var ia=Int(mi(meta,3,a));var ib=Int(mi(meta,3,b));var aa=load(candidate,ia);var bb=load(candidate,ib)
            if ia==ib or (aa.mass==0 and bb.mass==0):continue
            var gap=values[unsafe_offset=1+p*7+6];stats[unsafe_offset=3]=max(stats[unsafe_offset=3],max(0.0,-gap))
            if gap < -SLOP-POS_TOL:summary[unsafe_offset=0]=BR_POST;return
            var n=raw_normal(values,p);var origin=raw_origin(values,p);var oa=load(projected,ia);var ob=load(projected,ib)
            for i in range(Int(counts[unsafe_offset=p+1])):
                var k=1+(p*9+i)*7;var wa=Vec3(raw_points[unsafe_offset=k],raw_points[unsafe_offset=k+1],raw_points[unsafe_offset=k+2]);var wb=Vec3(raw_points[unsafe_offset=k+3],raw_points[unsafe_offset=k+4],raw_points[unsafe_offset=k+5]);var midpoint=origin+(wa+wb)*.5
                var incoming=normal_speed(oa,ob,midpoint,n);var target=-e*incoming if incoming<-.2 else 0.0
                if normal_speed(aa,bb,midpoint,n)<target-stats[unsafe_offset=5]:summary[unsafe_offset=0]=BR_POST;return
