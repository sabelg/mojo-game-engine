"""G03a GPU sphere ownership and bounded all-pairs AABB/contact detection.

Detection only. No response, scalable-broadphase claim or persistent manifold cache.
"""
from max.gpu import block_idx,block_dim,thread_idx
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion
from .core import finite,qfinite,qscale,rotation
from .kernels import load,CAPACITY

comptime SHAPES=64
comptime SHAPE_STRIDE=SHAPES+2
comptime META_FIELDS=7
comptime VALUE_FIELDS=11
comptime BOUNDS_FIELDS=22
comptime PAIRS=SHAPES*(SHAPES-1)//2
comptime PAIR_HEADER=11
comptime CONTACT_FIELDS=10
comptime SPHERE=UInt64(1)
comptime BOX=UInt64(2)
comptime ATTACH=UInt64(1)
comptime DETACH=UInt64(2)
comptime RESHAPE=UInt64(3)
comptime SHAPE_STALE=Int32(31)
comptime SHAPE_RANGE=Int32(32)
comptime BODY_STALE=Int32(33)
comptime SHAPE_FULL=Int32(34)
comptime BAD_SHAPE=Int32(35)
comptime DUPLICATE_BODY=Int32(36)
comptime REVISION_FULL=Int32(37)
comptime SHAPE_WORLD=Int32(38)
comptime SHAPE_KIND=Int32(39)
comptime PAIR_OVERFLOW=Int32(40)
comptime CONTACT_OVERFLOW=Int32(41)
comptime GEOMETRY_RANGE=Int32(42)
comptime POISON=Float64(-987654321.25)

def mi(meta: Pointer[UInt64,MutAnyOrigin],f: Int,s: Int) -> UInt64:
    return meta[unsafe_offset=f*SHAPE_STRIDE+s+1]
def vi(values: Pointer[Float64,MutAnyOrigin],f: Int,s: Int) -> Float64:
    return values[unsafe_offset=f*SHAPE_STRIDE+s+1]
def shape_valid(radius: Float64,offset: Vec3) -> Bool:
    return isfinite(radius) and radius>=1e-6 and radius<=1e4 and finite(offset) and max(abs(offset.x),max(abs(offset.y),abs(offset.z)))<=1e6
def body_valid(slot: UInt64,generation: UInt64,owner: UInt64,active: Pointer[Int32,MutAnyOrigin],gens: Pointer[UInt64,MutAnyOrigin],ns: Pointer[UInt64,MutAnyOrigin]) -> Bool:
    if slot>=UInt64(CAPACITY) or owner!=ns[unsafe_offset=1] or generation==0:return False
    return active[unsafe_offset=Int(slot)+1]==1 and gens[unsafe_offset=Int(slot)+1]==generation

def initialize_shapes(meta: Pointer[UInt64,MutAnyOrigin]):
    var s=Int(block_idx.x*block_dim.x+thread_idx.x)
    if s>=SHAPES:return
    for f in range(META_FIELDS):meta[unsafe_offset=f*SHAPE_STRIDE+s+1]=0
    meta[unsafe_offset=SHAPE_STRIDE+s+1]=1

def clear_shape(meta: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],s: Int):
    var generation=mi(meta,1,s)
    meta[unsafe_offset=s+1]=2 if generation==UInt64.MAX else 0
    if generation!=UInt64.MAX:meta[unsafe_offset=SHAPE_STRIDE+s+1]=generation+1
    for f in range(2,META_FIELDS):meta[unsafe_offset=f*SHAPE_STRIDE+s+1]=0
    for f in range(VALUE_FIELDS):values[unsafe_offset=f*SHAPE_STRIDE+s+1]=POISON

def shape_transaction(meta: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],
                      pending: Pointer[UInt64,MutAnyOrigin],pending_values: Pointer[Float64,MutAnyOrigin],
                      active: Pointer[Int32,MutAnyOrigin],gens: Pointer[UInt64,MutAnyOrigin],ns: Pointer[UInt64,MutAnyOrigin],
                      headers: Pointer[UInt64,MutAnyOrigin],data: Pointer[Float64,MutAnyOrigin],results: Pointer[UInt64,MutAnyOrigin],
                      summary: Pointer[Int32,MutAnyOrigin],count: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    summary[unsafe_offset=0]=0;summary[unsafe_offset=1]=-1
    if count<0 or count>Int32(SHAPES):summary[unsafe_offset=0]=30;return
    for s in range(SHAPES):
        for f in range(META_FIELDS):pending[unsafe_offset=f*SHAPE_STRIDE+s+1]=mi(meta,f,s)
        for f in range(VALUE_FIELDS):pending_values[unsafe_offset=f*SHAPE_STRIDE+s+1]=vi(values,f,s)
        if mi(pending,0,s)==1 and not body_valid(mi(pending,3,s),mi(pending,4,s),mi(pending,5,s),active,gens,ns):
            clear_shape(pending,pending_values,s)
    for c in range(Int(count)):
        var h=1+c*7;var p=1+c*VALUE_FIELDS
        var op=headers[unsafe_offset=h];var target=headers[unsafe_offset=h+1];var gen=headers[unsafe_offset=h+2]
        var body_slot=headers[unsafe_offset=h+3];var body_gen=headers[unsafe_offset=h+4]
        var owner=headers[unsafe_offset=h+5];var kind=headers[unsafe_offset=h+6]
        var radius=data[unsafe_offset=p];var offset=Vec3(data[unsafe_offset=p+1],data[unsafe_offset=p+2],data[unsafe_offset=p+3])
        var half=Vec3(data[unsafe_offset=p+4],data[unsafe_offset=p+5],data[unsafe_offset=p+6])
        var local=Quaternion(data[unsafe_offset=p+7],data[unsafe_offset=p+8],data[unsafe_offset=p+9],data[unsafe_offset=p+10])
        var descriptor_ok=(kind==SPHERE and shape_valid(radius,offset)) or (kind==BOX and radius==0 and box_valid(half,offset,local))
        var error=Int32(0);var s=Int(-1)
        if op==ATTACH:
            if not body_valid(body_slot,body_gen,owner,active,gens,ns):error=BODY_STALE
            elif not descriptor_ok:error=BAD_SHAPE
            else:
                for i in range(SHAPES):
                    if mi(pending,0,i)==1 and mi(pending,3,i)==body_slot and mi(pending,4,i)==body_gen:error=DUPLICATE_BODY
                if not error:
                    for i in range(SHAPES):
                        if mi(pending,0,i)==0:s=i;break
                    if s<0:error=SHAPE_FULL
                    else:
                        pending[unsafe_offset=s+1]=1;pending[unsafe_offset=2*SHAPE_STRIDE+s+1]=1
                        pending[unsafe_offset=3*SHAPE_STRIDE+s+1]=body_slot;pending[unsafe_offset=4*SHAPE_STRIDE+s+1]=body_gen
                        pending[unsafe_offset=5*SHAPE_STRIDE+s+1]=owner;pending[unsafe_offset=6*SHAPE_STRIDE+s+1]=kind
        elif op==DETACH or op==RESHAPE:
            if owner!=ns[unsafe_offset=1]:error=SHAPE_WORLD
            elif target>=UInt64(SHAPES):error=SHAPE_RANGE
            else:
                s=Int(target)
                if mi(pending,0,s)!=1 or gen==0 or mi(pending,1,s)!=gen:error=SHAPE_STALE
                elif op==DETACH:clear_shape(pending,pending_values,s)
                elif not descriptor_ok:error=BAD_SHAPE
                elif kind!=mi(pending,6,s):error=SHAPE_KIND
                elif mi(pending,2,s)==UInt64.MAX:error=REVISION_FULL
                else:pending[unsafe_offset=2*SHAPE_STRIDE+s+1]=mi(pending,2,s)+1
        else:error=30
        if error:
            summary[unsafe_offset=0]=error;summary[unsafe_offset=1]=Int32(c);return
        if op==ATTACH or op==RESHAPE:
            pending_values[unsafe_offset=s+1]=radius;pending_values[unsafe_offset=SHAPE_STRIDE+s+1]=offset.x
            pending_values[unsafe_offset=2*SHAPE_STRIDE+s+1]=offset.y;pending_values[unsafe_offset=3*SHAPE_STRIDE+s+1]=offset.z
            for f in range(4,VALUE_FIELDS):pending_values[unsafe_offset=f*SHAPE_STRIDE+s+1]=data[unsafe_offset=p+f]
        var r=1+c*4
        results[unsafe_offset=r]=UInt64(s);results[unsafe_offset=r+1]=mi(pending,1,s)
        results[unsafe_offset=r+2]=ns[unsafe_offset=1];results[unsafe_offset=r+3]=mi(pending,2,s)
    for s in range(SHAPES):
        for f in range(META_FIELDS):meta[unsafe_offset=f*SHAPE_STRIDE+s+1]=mi(pending,f,s)
        for f in range(VALUE_FIELDS):values[unsafe_offset=f*SHAPE_STRIDE+s+1]=vi(pending_values,f,s)

def prepare_bounds(current: Pointer[Float64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],
                   bounds: Pointer[Float64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin]):
    var s=Int(block_idx.x*block_dim.x+thread_idx.x)
    if s>=SHAPES:return
    statuses[unsafe_offset=s+1]=0
    if mi(meta,0,s)!=1:return
    var body=load(current,Int(mi(meta,3,s)))
    var radius=vi(values,0,s);var offset=Vec3(vi(values,1,s),vi(values,2,s),vi(values,3,s))
    var half=Vec3(vi(values,4,s),vi(values,5,s),vi(values,6,s))
    var local=Quaternion(vi(values,7,s),vi(values,8,s),vi(values,9,s),vi(values,10,s))
    var kind=mi(meta,6,s)
    if not body.valid() or (kind==SPHERE and not shape_valid(radius,offset)) or (kind==BOX and not box_valid(half,offset,local)) or (kind!=SPHERE and kind!=BOX):
        statuses[unsafe_offset=s+1]=BAD_SHAPE;return
    var center=body.position+body.orientation.rotate(offset)
    var x=Vec3(1,0,0);var y=Vec3(0,1,0);var z=Vec3(0,0,1);var extent=Vec3(radius,radius,radius)
    if kind==BOX:
        var rb=rotation(body.orientation);var q=rotation(rb*rotation(local))
        center=body.position+rb.rotate(offset)
        x=q.rotate(x);y=q.rotate(y);z=q.rotate(z)
        extent=Vec3(abs(x.x)*half.x+abs(y.x)*half.y+abs(z.x)*half.z,
            abs(x.y)*half.x+abs(y.y)*half.y+abs(z.y)*half.z,abs(x.z)*half.x+abs(y.z)*half.y+abs(z.z)*half.z)
    if not finite(center) or max(abs(center.x),max(abs(center.y),abs(center.z)))>1e9:
        statuses[unsafe_offset=s+1]=GEOMETRY_RANGE;return
    var b=1+s*BOUNDS_FIELDS
    bounds[unsafe_offset=b]=center.x;bounds[unsafe_offset=b+1]=center.y;bounds[unsafe_offset=b+2]=center.z;bounds[unsafe_offset=b+3]=radius
    bounds[unsafe_offset=b+4]=center.x-extent.x;bounds[unsafe_offset=b+5]=center.y-extent.y;bounds[unsafe_offset=b+6]=center.z-extent.z
    bounds[unsafe_offset=b+7]=center.x+extent.x;bounds[unsafe_offset=b+8]=center.y+extent.y;bounds[unsafe_offset=b+9]=center.z+extent.z
    bounds[unsafe_offset=b+10]=half.x;bounds[unsafe_offset=b+11]=half.y;bounds[unsafe_offset=b+12]=half.z
    bounds[unsafe_offset=b+13]=x.x;bounds[unsafe_offset=b+14]=x.y;bounds[unsafe_offset=b+15]=x.z
    bounds[unsafe_offset=b+16]=y.x;bounds[unsafe_offset=b+17]=y.y;bounds[unsafe_offset=b+18]=y.z
    bounds[unsafe_offset=b+19]=z.x;bounds[unsafe_offset=b+20]=z.y;bounds[unsafe_offset=b+21]=z.z

def pair_geometry(meta: Pointer[UInt64,MutAnyOrigin],bounds: Pointer[Float64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin],
                  candidates: Pointer[Int32,MutAnyOrigin],contacts: Pointer[Int32,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin]):
    var index=Int(block_idx.x*block_dim.x+thread_idx.x)
    var a=index//SHAPES;var b=index%SHAPES
    if a>=SHAPES or b<=a:return
    var p=a*(2*SHAPES-a-1)//2+b-a-1
    candidates[unsafe_offset=p+1]=0;contacts[unsafe_offset=p+1]=0
    if mi(meta,0,a)!=1 or mi(meta,0,b)!=1 or statuses[unsafe_offset=a+1]!=0 or statuses[unsafe_offset=b+1]!=0:return
    var kind_a=mi(meta,6,a);var kind_b=mi(meta,6,b)
    if kind_a==BOX and kind_b==BOX:return
    var aa=1+a*BOUNDS_FIELDS;var bb=1+b*BOUNDS_FIELDS
    for axis in range(3):
        if bounds[unsafe_offset=aa+4+axis]>bounds[unsafe_offset=bb+7+axis] or bounds[unsafe_offset=bb+4+axis]>bounds[unsafe_offset=aa+7+axis]:return
    candidates[unsafe_offset=p+1]=1
    if kind_a==BOX or kind_b==BOX:
        var hit=sphere_box(bounds,b if kind_a==BOX else a,a if kind_a==BOX else b)
        if hit.separation>0:return
        contacts[unsafe_offset=p+1]=1
        var normal=hit.normal*(-1) if kind_a==BOX else hit.normal
        var wa=hit.box_point if kind_a==BOX else hit.sphere_point
        var wb=hit.sphere_point if kind_a==BOX else hit.box_point
        var g=1+p*CONTACT_FIELDS
        geometry[unsafe_offset=g]=normal.x;geometry[unsafe_offset=g+1]=normal.y;geometry[unsafe_offset=g+2]=normal.z;geometry[unsafe_offset=g+3]=hit.separation
        geometry[unsafe_offset=g+4]=wa.x;geometry[unsafe_offset=g+5]=wa.y;geometry[unsafe_offset=g+6]=wa.z
        geometry[unsafe_offset=g+7]=wb.x;geometry[unsafe_offset=g+8]=wb.y;geometry[unsafe_offset=g+9]=wb.z
        return
    var ca=Vec3(bounds[unsafe_offset=aa],bounds[unsafe_offset=aa+1],bounds[unsafe_offset=aa+2])
    var cb=Vec3(bounds[unsafe_offset=bb],bounds[unsafe_offset=bb+1],bounds[unsafe_offset=bb+2])
    var ra=bounds[unsafe_offset=aa+3];var rb=bounds[unsafe_offset=bb+3]
    var delta=cb-ca;var distance=sqrt(delta.dot(delta))
    var separation=distance-(ra+rb)
    if separation>0:return
    contacts[unsafe_offset=p+1]=1
    var normal=Vec3(1,0,0) if distance==0 else Vec3(delta.x/distance,delta.y/distance,delta.z/distance)
    var wa=ca+normal*ra;var wb=cb-normal*rb
    var g=1+p*CONTACT_FIELDS
    geometry[unsafe_offset=g]=normal.x;geometry[unsafe_offset=g+1]=normal.y;geometry[unsafe_offset=g+2]=normal.z;geometry[unsafe_offset=g+3]=separation
    geometry[unsafe_offset=g+4]=wa.x;geometry[unsafe_offset=g+5]=wa.y;geometry[unsafe_offset=g+6]=wa.z
    geometry[unsafe_offset=g+7]=wb.x;geometry[unsafe_offset=g+8]=wb.y;geometry[unsafe_offset=g+9]=wb.z

def write_pair(output: Pointer[UInt64,MutAnyOrigin],record: Int,a: Int,b: Int,meta: Pointer[UInt64,MutAnyOrigin]):
    var k=1+record*PAIR_HEADER
    output[unsafe_offset=k]=UInt64(a);output[unsafe_offset=k+1]=mi(meta,1,a);output[unsafe_offset=k+2]=mi(meta,2,a)
    output[unsafe_offset=k+3]=mi(meta,3,a);output[unsafe_offset=k+4]=mi(meta,4,a)
    output[unsafe_offset=k+5]=UInt64(b);output[unsafe_offset=k+6]=mi(meta,1,b);output[unsafe_offset=k+7]=mi(meta,2,b)
    output[unsafe_offset=k+8]=mi(meta,3,b);output[unsafe_offset=k+9]=mi(meta,4,b);output[unsafe_offset=k+10]=mi(meta,5,a)

def compact_detection(meta: Pointer[UInt64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin],candidates: Pointer[Int32,MutAnyOrigin],
                      contacts: Pointer[Int32,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],pair_output: Pointer[UInt64,MutAnyOrigin],
                      contact_output: Pointer[UInt64,MutAnyOrigin],contact_values: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],
                      pair_limit: Int32,contact_limit: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    summary[unsafe_offset=0]=0;summary[unsafe_offset=1]=0;summary[unsafe_offset=2]=0;summary[unsafe_offset=3]=-1
    for s in range(SHAPES):
        if statuses[unsafe_offset=s+1]!=0:
            summary[unsafe_offset=0]=statuses[unsafe_offset=s+1];summary[unsafe_offset=3]=Int32(s);return
    var pairs=Int(0);var hits=Int(0)
    for a in range(SHAPES):
        for b in range(a+1,SHAPES):
            var p=a*(2*SHAPES-a-1)//2+b-a-1
            if candidates[unsafe_offset=p+1]:
                if pairs>=Int(pair_limit):summary[unsafe_offset=0]=PAIR_OVERFLOW;return
                write_pair(pair_output,pairs,a,b,meta);pairs+=1
            if contacts[unsafe_offset=p+1]:
                if hits>=Int(contact_limit):summary[unsafe_offset=0]=CONTACT_OVERFLOW;return
                write_pair(contact_output,hits,a,b,meta)
                for f in range(CONTACT_FIELDS):contact_values[unsafe_offset=1+hits*CONTACT_FIELDS+f]=geometry[unsafe_offset=1+p*CONTACT_FIELDS+f]
                hits+=1
    summary[unsafe_offset=1]=Int32(pairs);summary[unsafe_offset=2]=Int32(hits)

def shape_snapshot(meta: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],output: Pointer[UInt64,MutAnyOrigin],out_values: Pointer[Float64,MutAnyOrigin]):
    var s=Int(block_idx.x*block_dim.x+thread_idx.x)
    if s>=SHAPES:return
    for f in range(META_FIELDS):output[unsafe_offset=f*SHAPE_STRIDE+s+1]=mi(meta,f,s)
    for f in range(VALUE_FIELDS):out_values[unsafe_offset=f*SHAPE_STRIDE+s+1]=vi(values,f,s)
    if s==0:
        for f in range(META_FIELDS):
            output[unsafe_offset=f*SHAPE_STRIDE]=meta[unsafe_offset=f*SHAPE_STRIDE]
            output[unsafe_offset=f*SHAPE_STRIDE+SHAPE_STRIDE-1]=meta[unsafe_offset=f*SHAPE_STRIDE+SHAPE_STRIDE-1]
        for f in range(VALUE_FIELDS):
            out_values[unsafe_offset=f*SHAPE_STRIDE]=values[unsafe_offset=f*SHAPE_STRIDE]
            out_values[unsafe_offset=f*SHAPE_STRIDE+SHAPE_STRIDE-1]=values[unsafe_offset=f*SHAPE_STRIDE+SHAPE_STRIDE-1]

def box_valid(half: Vec3,offset: Vec3,q: Quaternion) -> Bool:
    return finite(half) and min(half.x,min(half.y,half.z))>=1e-6 and max(half.x,max(half.y,half.z))<=1e4 and finite(offset) and max(abs(offset.x),max(abs(offset.y),abs(offset.z)))<=1e6 and qfinite(q) and qscale(q)>=1e-12 and qscale(q)<=1e12

@fieldwise_init
struct BoxHit(ImplicitlyCopyable,Movable):
    var normal: Vec3
    var separation: Float64
    var sphere_point: Vec3
    var box_point: Vec3

def sphere_box(bounds: Pointer[Float64,MutAnyOrigin],sphere: Int,box: Int) -> BoxHit:
    var s=1+sphere*BOUNDS_FIELDS;var b=1+box*BOUNDS_FIELDS
    var center=Vec3(bounds[unsafe_offset=s],bounds[unsafe_offset=s+1],bounds[unsafe_offset=s+2])
    var origin=Vec3(bounds[unsafe_offset=b],bounds[unsafe_offset=b+1],bounds[unsafe_offset=b+2])
    var half=Vec3(bounds[unsafe_offset=b+10],bounds[unsafe_offset=b+11],bounds[unsafe_offset=b+12])
    var x=Vec3(bounds[unsafe_offset=b+13],bounds[unsafe_offset=b+14],bounds[unsafe_offset=b+15])
    var y=Vec3(bounds[unsafe_offset=b+16],bounds[unsafe_offset=b+17],bounds[unsafe_offset=b+18])
    var z=Vec3(bounds[unsafe_offset=b+19],bounds[unsafe_offset=b+20],bounds[unsafe_offset=b+21])
    var delta=center-origin;var u=Vec3(delta.dot(x),delta.dot(y),delta.dot(z))
    var q=Vec3(max(-half.x,min(half.x,u.x)),max(-half.y,min(half.y,u.y)),max(-half.z,min(half.z,u.z)))
    var outside=abs(u.x)>half.x or abs(u.y)>half.y or abs(u.z)>half.z
    var radius=bounds[unsafe_offset=s+3]
    var normal=Vec3(0,0,0);var separation=Float64(0);var point=origin
    if outside:
        var d=u-q;var distance=sqrt(d.dot(d))
        var outward=(x*d.x+y*d.y+z*d.z)*(1/distance)
        normal=outward*(-1);separation=distance-radius
        point=origin+x*q.x+y*q.y+z*q.z
    else:
        # Exact ties choose local X, then Y, then Z; zero chooses positive face.
        var clearance=half.x-abs(u.x);var outward=x*(1.0 if u.x>=0 else -1.0)
        if half.y-abs(u.y)<clearance:
            clearance=half.y-abs(u.y);outward=y*(1.0 if u.y>=0 else -1.0)
        if half.z-abs(u.z)<clearance:
            clearance=half.z-abs(u.z);outward=z*(1.0 if u.z>=0 else -1.0)
        normal=outward*(-1);separation=-(clearance+radius);point=center+outward*clearance
    return BoxHit(normal,separation,center+normal*radius,point)
