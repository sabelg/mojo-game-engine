"""Separate bounded GPU box/box SAT and contact-patch geometry; no response."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from max.gpu import block_idx,block_dim,thread_idx
from mojo_game import Vec3
from .shape_kernels import SHAPES,PAIRS,BOX,BOUNDS_FIELDS,mi,write_pair,PAIR_HEADER,POISON

comptime PATCH_POINTS=9
comptime PATCH_FIELDS=7
comptime BB_GEOMETRY=Int32(100)
comptime BB_PAIRS_FULL=Int32(101)
comptime BB_POINTS_FULL=Int32(102)
comptime BB_EPOCH_FULL=Int32(103)
comptime EPS=Float64(2.220446049250313e-16)

@fieldwise_init
struct BoxGeometry(ImplicitlyCopyable,Movable):
    var center: Vec3
    var half: Vec3
    var x: Vec3
    var y: Vec3
    var z: Vec3
    def axis(self,i: Int) -> Vec3:
        return self.x if i==0 else self.y if i==1 else self.z
    def width(self,i: Int) -> Float64:
        return self.half.x if i==0 else self.half.y if i==1 else self.half.z

def box(bounds: Pointer[Float64,MutAnyOrigin],slot: Int) -> BoxGeometry:
    var k=1+slot*BOUNDS_FIELDS
    return BoxGeometry(Vec3(bounds[unsafe_offset=k],bounds[unsafe_offset=k+1],bounds[unsafe_offset=k+2]),
        Vec3(bounds[unsafe_offset=k+10],bounds[unsafe_offset=k+11],bounds[unsafe_offset=k+12]),
        Vec3(bounds[unsafe_offset=k+13],bounds[unsafe_offset=k+14],bounds[unsafe_offset=k+15]),
        Vec3(bounds[unsafe_offset=k+16],bounds[unsafe_offset=k+17],bounds[unsafe_offset=k+18]),
        Vec3(bounds[unsafe_offset=k+19],bounds[unsafe_offset=k+20],bounds[unsafe_offset=k+21]))
def unit(v: Vec3) -> Vec3:
    var scale=max(abs(v.x),max(abs(v.y),abs(v.z)))
    if scale==0:return Vec3(0,0,0)
    var a=Vec3(v.x/scale,v.y/scale,v.z/scale)
    return a*(1/sqrt(a.x*a.x+a.y*a.y+a.z*a.z))
def face_normal(b: BoxGeometry,i: Int) -> Vec3:
    var n=unit(b.axis((i+1)%3).cross(b.axis((i+2)%3)))
    return n if n.dot(b.axis(i))>=0 else n*(-1)
def radius(b: BoxGeometry,n: Vec3) -> Float64:
    return abs(n.dot(b.x))*b.half.x+abs(n.dot(b.y))*b.half.y+abs(n.dot(b.z))*b.half.z

@fieldwise_init
struct SatResult(ImplicitlyCopyable,Movable):
    var hit: Bool
    var normal: Vec3
    var gap: Float64
    var feature: Int32
    var ambiguous: Bool

def sat(a: BoxGeometry,b: BoxGeometry) -> SatResult:
    var delta=b.center-a.center;var best=Float64(-1e300);var selected=Vec3(1,0,0);var feature=Int32(0);var ambiguous=False
    for code in range(15):
        var n=face_normal(a,code) if code<3 else face_normal(b,code-3) if code<6 else unit(a.axis((code-6)//3).cross(b.axis((code-6)%3)))
        if n.x==0 and n.y==0 and n.z==0:continue
        var distance=delta.dot(n);var ra=radius(a,n);var rb=radius(b,n);var gap=abs(distance)-ra-rb
        if gap>0:return SatResult(False,n,gap,Int32(code),False)
        var band=32*EPS*(1+abs(distance)+ra+rb)
        if code==0 or gap>best+(band if code>=6 else 0):
            best=gap;selected=n if distance>=0 else n*(-1);feature=Int32(code);ambiguous=distance==0
        elif abs(gap-best)<=band:ambiguous=True
    return SatResult(True,selected,best,feature,ambiguous)

struct Patch(Movable):
    var a: Array[Vec3,PATCH_POINTS]
    var b: Array[Vec3,PATCH_POINTS]
    var separation: Array[Float64,PATCH_POINTS]
    var count: Int32
    var coalesced: Bool
    var error: Int32
    def __init__(out self):
        self.a=Array[Vec3,PATCH_POINTS](fill=Vec3(0,0,0));self.b=Array[Vec3,PATCH_POINTS](fill=Vec3(0,0,0));self.separation=Array[Float64,PATCH_POINTS](fill=0)
        self.count=0;self.coalesced=False;self.error=0

def same_point(a: Vec3,b: Vec3,resolution: Float64) -> Bool:
    return max(abs(a.x-b.x),max(abs(a.y-b.y),abs(a.z-b.z)))<=resolution

def face_patch(a: BoxGeometry,b: BoxGeometry,s: SatResult) -> Patch:
    var result=Patch();var axis=Int(s.feature);var reference=a;var incident=b;var outward=s.normal;var reverse=False
    if axis>=3:axis-=3;reference=b;incident=a;outward=s.normal*(-1);reverse=True
    # All vertices are relative to pair A's center, including a B reference face.
    var reference_origin=reference.center-a.center;var incident_origin=incident.center-a.center
    var face_sign=1.0 if outward.dot(reference.axis(axis))>=0 else -1.0
    var reference_center=reference_origin+reference.axis(axis)*(reference.width(axis)*face_sign)
    var incident_axis=0;var alignment=abs(outward.dot(face_normal(incident,0)))
    for i in range(1,3):
        var value=abs(outward.dot(face_normal(incident,i)))
        if value>alignment:alignment=value;incident_axis=i
    var sign=-1.0 if outward.dot(incident.axis(incident_axis))>=0 else 1.0
    var incident_center=incident_origin+incident.axis(incident_axis)*(incident.width(incident_axis)*sign)
    var u=incident.axis((incident_axis+1)%3)*incident.width((incident_axis+1)%3)
    var v=incident.axis((incident_axis+2)%3)*incident.width((incident_axis+2)%3)
    var polygon=Array[Vec3,16](fill=Vec3(0,0,0));var scratch=Array[Vec3,16](fill=Vec3(0,0,0));var count=4
    polygon[0]=incident_center+u+v;polygon[1]=incident_center-u+v;polygon[2]=incident_center-u-v;polygon[3]=incident_center+u-v
    var e0=reference.axis((axis+1)%3);var e1=reference.axis((axis+2)%3)
    var side0=unit(e1.cross(outward));var side1=unit(outward.cross(e0))
    if side0.dot(e0)<0:side0=side0*(-1)
    if side1.dot(e1)<0:side1=side1*(-1)
    var width0=abs(side0.dot(e0))*reference.width((axis+1)%3);var width1=abs(side1.dot(e1))*reference.width((axis+2)%3)
    var resolution=32*EPS*max(1.0,max(max(a.half.x,max(a.half.y,a.half.z)),max(b.half.x,max(b.half.y,b.half.z))))
    for plane in range(5):
        var n=side0 if plane<2 else side1 if plane<4 else outward
        if plane==1 or plane==3:n=n*(-1)
        var limit=width0 if plane<2 else width1 if plane<4 else 0.0
        var out_count=0
        for i in range(count):
            var previous=polygon[(i+count-1)%count];var current=polygon[i]
            var d0=limit-n.dot(previous-reference_center);var d1=limit-n.dot(current-reference_center)
            var inside0=d0>=0;var inside1=d1>=0
            if inside0!=inside1:
                var point=previous if d0==0 else current if d1==0 else previous+(current-previous)*(d0/(d0-d1))
                if out_count>=16:result.error=BB_GEOMETRY;return result^
                scratch[out_count]=point;out_count+=1
            if inside1:
                if out_count>=16:result.error=BB_GEOMETRY;return result^
                scratch[out_count]=current;out_count+=1
        count=0
        for i in range(out_count):
            var duplicate=False
            for j in range(count):
                if same_point(scratch[i],polygon[j],resolution):duplicate=True;result.coalesced=True
            if not duplicate:polygon[count]=scratch[i];count+=1
        if count==0:result.error=BB_GEOMETRY;return result^
        # A convex n-gon intersected with one halfspace has at most n+1
        # vertices. The quad therefore has at most 4+5=9 after five planes.
        if count>5+plane:result.error=BB_GEOMETRY;return result^
    # Remove redundant collinear construction vertices, not just exact duplicate
    # endpoints. This retains the corners of a resolved convex patch.
    for _ in range(16):
        if count<=2:break
        var removed=False
        for i in range(count):
            var previous=polygon[(i+count-1)%count];var current=polygon[i];var next=polygon[(i+1)%count]
            var span=next-previous;var length=sqrt(span.dot(span))
            if length==0:continue
            var direction=span*(1/length);var offset=current-previous
            var distance=offset.cross(direction);var position=offset.dot(direction)
            if sqrt(distance.dot(distance))<=resolution and position>=-resolution and position<=length+resolution:
                for j in range(i,count-1):polygon[j]=polygon[j+1]
                count-=1;removed=True;result.coalesced=True;break
        if not removed:break
    if count>PATCH_POINTS:result.error=BB_GEOMETRY;return result^
    for i in range(count):
        var incident_point=polygon[i];var separation=outward.dot(incident_point-reference_center)
        var reference_point=incident_point-outward*separation
        if separation>0:
            if separation>resolution:result.error=BB_GEOMETRY;return result^
            # The contact-plane dot can round a clipped endpoint slightly
            # outward. Coalesce that representation-scale distance to touch.
            incident_point=reference_point;separation=0;result.coalesced=True
        result.a[i]=incident_point if reverse else reference_point
        result.b[i]=reference_point if reverse else incident_point
        result.separation[i]=separation
    result.count=Int32(count)
    return result^

def edge_patch(a: BoxGeometry,b: BoxGeometry,s: SatResult) -> Patch:
    var result=Patch();var ia=(Int(s.feature)-6)//3;var ib=(Int(s.feature)-6)%3;var n=s.normal
    var ca=Vec3(0,0,0);var cb=b.center-a.center
    for i in range(3):
        if i!=ia:ca=ca+a.axis(i)*(a.width(i)*(1.0 if n.dot(a.axis(i))>=0 else -1.0))
        if i!=ib:cb=cb+b.axis(i)*(b.width(i)*(-1.0 if n.dot(b.axis(i))>=0 else 1.0))
    var u=unit(a.axis(ia));var v=unit(b.axis(ib));var transverse=unit(n.cross(u));var delta=cb-ca
    var divisor=v.dot(transverse)
    if divisor==0:result.error=BB_GEOMETRY;return result^
    var t=-delta.dot(transverse)/divisor;var q=cb+v*t;var f=(q-ca).dot(u)
    var ha=a.width(ia)*sqrt(a.axis(ia).dot(a.axis(ia)));var hb=b.width(ib)*sqrt(b.axis(ib).dot(b.axis(ib)))
    var band=64*EPS*(1+ha+hb)
    if not isfinite(t) or not isfinite(f) or abs(t)>hb+band or abs(f)>ha+band:result.error=BB_GEOMETRY;return result^
    t=max(-hb,min(hb,t));f=max(-ha,min(ha,f))
    result.a[0]=ca+u*f;result.b[0]=cb+v*t;result.separation[0]=(result.b[0]-result.a[0]).dot(n);result.count=1
    if result.separation[0]>0:result.error=BB_GEOMETRY
    return result^

def sort_patch(mut p: Patch,resolution: Float64=0):
    for i in range(Int(p.count)):
        for j in range(i+1,Int(p.count)):
            var a=(p.a[i]+p.b[i])*.5;var b=(p.a[j]+p.b[j])*.5
            if b.x<a.x or (b.x==a.x and b.y<a.y) or (b.x==a.x and b.y==a.y and b.z<a.z):
                var wa=p.a[i];var wb=p.b[i];var sep=p.separation[i]
                p.a[i]=p.a[j];p.b[i]=p.b[j];p.separation[i]=p.separation[j]
                p.a[j]=wa;p.b[j]=wb;p.separation[j]=sep
    # Witness projection can contract incident-vertex distances. Enforce
    # uniqueness in the actual published midpoint representation as well.
    var kept=0
    for i in range(Int(p.count)):
        var midpoint=(p.a[i]+p.b[i])*.5;var duplicate=False
        for j in range(kept):
            if same_point(midpoint,(p.a[j]+p.b[j])*.5,resolution):duplicate=True
        if duplicate:p.coalesced=True;continue
        p.a[kept]=p.a[i];p.b[kept]=p.b[i];p.separation[kept]=p.separation[i];kept+=1
    p.count=Int32(kept)

def box_pairs(meta: Pointer[UInt64,MutAnyOrigin],bounds: Pointer[Float64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin],
              flags: Pointer[Int32,MutAnyOrigin],counts: Pointer[Int32,MutAnyOrigin],errors: Pointer[Int32,MutAnyOrigin],features: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],points: Pointer[Float64,MutAnyOrigin]):
    var index=Int(block_idx.x*block_dim.x+thread_idx.x);var a=index//SHAPES;var b=index%SHAPES
    if a>=SHAPES or b<=a:return
    var p=a*(2*SHAPES-a-1)//2+b-a-1;flags[unsafe_offset=p+1]=0;counts[unsafe_offset=p+1]=0;errors[unsafe_offset=p+1]=0
    if mi(meta,0,a)!=1 or mi(meta,0,b)!=1 or mi(meta,6,a)!=BOX or mi(meta,6,b)!=BOX or statuses[unsafe_offset=a+1]!=0 or statuses[unsafe_offset=b+1]!=0:return
    var aa=box(bounds,a);var bb=box(bounds,b);var s=sat(aa,bb)
    if not s.hit:return
    var patch=face_patch(aa,bb,s) if s.feature<6 else edge_patch(aa,bb,s)
    if patch.error!=0:errors[unsafe_offset=p+1]=patch.error;return
    var resolution=32*EPS*max(1.0,max(max(aa.half.x,max(aa.half.y,aa.half.z)),max(bb.half.x,max(bb.half.y,bb.half.z))))
    sort_patch(patch,resolution);flags[unsafe_offset=p+1]=1;counts[unsafe_offset=p+1]=patch.count
    features[unsafe_offset=1+p*2]=UInt64(s.feature);features[unsafe_offset=2+p*2]=UInt64(1 if s.ambiguous else 0)+UInt64(2 if patch.coalesced else 0)
    var h=1+p*7;values[unsafe_offset=h]=aa.center.x;values[unsafe_offset=h+1]=aa.center.y;values[unsafe_offset=h+2]=aa.center.z
    values[unsafe_offset=h+3]=s.normal.x;values[unsafe_offset=h+4]=s.normal.y;values[unsafe_offset=h+5]=s.normal.z;values[unsafe_offset=h+6]=s.gap
    for i in range(Int(patch.count)):
        var k=1+(p*PATCH_POINTS+i)*PATCH_FIELDS
        points[unsafe_offset=k]=patch.a[i].x;points[unsafe_offset=k+1]=patch.a[i].y;points[unsafe_offset=k+2]=patch.a[i].z
        points[unsafe_offset=k+3]=patch.b[i].x;points[unsafe_offset=k+4]=patch.b[i].y;points[unsafe_offset=k+5]=patch.b[i].z;points[unsafe_offset=k+6]=patch.separation[i]

comptime BB_HEADER=PAIR_HEADER+4

def initialize_box_state(state: Pointer[UInt64,MutAnyOrigin]):
    for i in range(1,4):state[unsafe_offset=i]=0

def publish_boxes(meta: Pointer[UInt64,MutAnyOrigin],shape_status: Pointer[Int32,MutAnyOrigin],flags: Pointer[Int32,MutAnyOrigin],counts: Pointer[Int32,MutAnyOrigin],errors: Pointer[Int32,MutAnyOrigin],features: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],points: Pointer[Float64,MutAnyOrigin],
                  headers: Pointer[UInt64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin],point_output: Pointer[Float64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],pair_limit: Int32,point_limit: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    summary[unsafe_offset=0]=0
    if state[unsafe_offset=1]==UInt64.MAX:summary[unsafe_offset=0]=BB_EPOCH_FULL;return
    for s in range(SHAPES):
        if shape_status[unsafe_offset=s+1]!=0:summary[unsafe_offset=0]=shape_status[unsafe_offset=s+1];return
    var pairs=0;var total=0
    for p in range(PAIRS):
        if errors[unsafe_offset=p+1]!=0:summary[unsafe_offset=0]=errors[unsafe_offset=p+1];return
        if flags[unsafe_offset=p+1]!=0:
            if flags[unsafe_offset=p+1]!=1 or features[unsafe_offset=1+p*2]>=15:summary[unsafe_offset=0]=BB_GEOMETRY;return
            var count=Int(counts[unsafe_offset=p+1])
            if count<1 or count>PATCH_POINTS:summary[unsafe_offset=0]=BB_GEOMETRY;return
            for f in range(7):
                if not isfinite(values[unsafe_offset=1+p*7+f]):summary[unsafe_offset=0]=BB_GEOMETRY;return
            var k=1+p*7
            var nx=values[unsafe_offset=k+3];var ny=values[unsafe_offset=k+4];var nz=values[unsafe_offset=k+5]
            if abs(nx*nx+ny*ny+nz*nz-1)>128*EPS:summary[unsafe_offset=0]=BB_GEOMETRY;return
            for i in range(count):
                for f in range(PATCH_FIELDS):
                    if not isfinite(points[unsafe_offset=1+(p*PATCH_POINTS+i)*PATCH_FIELDS+f]):summary[unsafe_offset=0]=BB_GEOMETRY;return
                if points[unsafe_offset=1+(p*PATCH_POINTS+i)*PATCH_FIELDS+6]>0:summary[unsafe_offset=0]=BB_GEOMETRY;return
            if values[unsafe_offset=1+p*7+6]>0:summary[unsafe_offset=0]=BB_GEOMETRY;return
            pairs+=1;total+=count
    if pairs>Int(pair_limit):summary[unsafe_offset=0]=BB_PAIRS_FULL;return
    if total>Int(point_limit):summary[unsafe_offset=0]=BB_POINTS_FULL;return
    # Validation completes before touching published headers, geometry or state.
    for i in range(1,Int(pair_limit)*BB_HEADER+1):headers[unsafe_offset=i]=UInt64.MAX
    for i in range(1,Int(pair_limit)*7+1):output[unsafe_offset=i]=POISON
    for i in range(1,Int(point_limit)*PATCH_FIELDS+1):point_output[unsafe_offset=i]=POISON
    var record=0;var point_index=0
    for a in range(SHAPES):
        for b in range(a+1,SHAPES):
            var p=a*(2*SHAPES-a-1)//2+b-a-1
            if flags[unsafe_offset=p+1]==0:continue
            var h=1+record*BB_HEADER;var count=Int(counts[unsafe_offset=p+1])
            headers[unsafe_offset=h]=UInt64(a);headers[unsafe_offset=h+1]=mi(meta,1,a);headers[unsafe_offset=h+2]=mi(meta,2,a);headers[unsafe_offset=h+3]=mi(meta,3,a);headers[unsafe_offset=h+4]=mi(meta,4,a)
            headers[unsafe_offset=h+5]=UInt64(b);headers[unsafe_offset=h+6]=mi(meta,1,b);headers[unsafe_offset=h+7]=mi(meta,2,b);headers[unsafe_offset=h+8]=mi(meta,3,b);headers[unsafe_offset=h+9]=mi(meta,4,b);headers[unsafe_offset=h+10]=mi(meta,5,a)
            headers[unsafe_offset=h+11]=features[unsafe_offset=1+p*2];headers[unsafe_offset=h+12]=features[unsafe_offset=2+p*2];headers[unsafe_offset=h+13]=UInt64(point_index);headers[unsafe_offset=h+14]=UInt64(count)
            for f in range(7):output[unsafe_offset=1+record*7+f]=values[unsafe_offset=1+p*7+f]
            for i in range(count):
                for f in range(PATCH_FIELDS):point_output[unsafe_offset=1+(point_index+i)*PATCH_FIELDS+f]=points[unsafe_offset=1+(p*PATCH_POINTS+i)*PATCH_FIELDS+f]
            record+=1;point_index+=count
    state[unsafe_offset=1]+=1;state[unsafe_offset=2]=UInt64(pairs);state[unsafe_offset=3]=UInt64(total)
