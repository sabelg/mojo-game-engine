"""Independent CPU corner-support SAT and constructive polygon enumeration.

Consumes input box basis/centers (not GPU SAT results, normals or patch points).
Transformed input bounds are checked independently by the geometry fixtures.
"""
from std.collections import Array,List
from std.math import sqrt
from mojo_game import Vec3

@fieldwise_init
struct ReferenceBox(ImplicitlyCopyable,Movable):
    var center: Vec3
    var e0: Vec3
    var e1: Vec3
    var e2: Vec3
    def edge(self,i: Int) -> Vec3:
        return self.e0 if i==0 else self.e1 if i==1 else self.e2
    def vertex(self,i: Int,origin: Vec3) -> Vec3:
        var x=self.e0*(1.0 if (i&1)!=0 else -1.0);var y=self.e1*(1.0 if (i&2)!=0 else -1.0);var z=self.e2*(1.0 if (i&4)!=0 else -1.0)
        return Vec3(self.center.x-origin.x+x.x+y.x+z.x,self.center.y-origin.y+x.y+y.y+z.y,self.center.z-origin.z+x.z+y.z+z.z)

def scalar_dot(a: Vec3,b: Vec3) -> Float64:
    return a.x*b.x+a.y*b.y+a.z*b.z
def scalar_cross(a: Vec3,b: Vec3) -> Vec3:
    return Vec3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
def direction(v: Vec3) -> Vec3:
    var scale=max(abs(v.x),max(abs(v.y),abs(v.z)))
    if scale==0:return Vec3(0,0,0)
    var x=v.x/scale;var y=v.y/scale;var z=v.z/scale;var length=sqrt(x*x+y*y+z*z)
    return Vec3(x/length,y/length,z/length)
def face(b: ReferenceBox,i: Int) -> Vec3:
    # Derive planes from independently enumerated corner edges.
    var v0=b.vertex(0,b.center);var u=b.vertex(1<<((i+1)%3),b.center)-v0;var v=b.vertex(1<<((i+2)%3),b.center)-v0
    var n=direction(scalar_cross(u,v));return n if scalar_dot(n,b.edge(i))>=0 else n*(-1)

def vertex_gap(a: ReferenceBox,b: ReferenceBox,n: Vec3) -> Float64:
    var lo_a=Float64(1e300);var hi_a=Float64(-1e300);var lo_b=Float64(1e300);var hi_b=Float64(-1e300)
    for i in range(8):
        var pa=scalar_dot(a.vertex(i,a.center),n);var pb=scalar_dot(b.vertex(i,a.center),n)
        lo_a=min(lo_a,pa);hi_a=max(hi_a,pa);lo_b=min(lo_b,pb);hi_b=max(hi_b,pb)
    return max(lo_b-hi_a,lo_a-hi_b)

def reference_sat(a: ReferenceBox,b: ReferenceBox) -> Tuple[Bool,Float64]:
    var greatest=Float64(-1e300)
    for i in range(6):
        var n=face(a,i) if i<3 else face(b,i-3);var gap=vertex_gap(a,b,n)
        if gap>0:return False,gap
        greatest=max(greatest,gap)
    # Enumerate actual corner edge vectors, not unit-axis radius coefficients.
    for i in range(3):
        var u=a.vertex(1<<i,a.center)-a.vertex(0,a.center)
        for j in range(3):
            var v=b.vertex(1<<j,a.center)-b.vertex(0,a.center);var n=direction(scalar_cross(u,v))
            if n.x==0 and n.y==0 and n.z==0:continue
            var gap=vertex_gap(a,b,n)
            if gap>0:return False,gap
            greatest=max(greatest,gap)
    return True,greatest

@fieldwise_init
struct P2(ImplicitlyCopyable,Movable):
    var x: Float64
    var y: Float64

def cross2(a: P2,b: P2,c: P2) -> Float64:
    return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
def inside(p: P2,polygon: Array[P2,4],resolution: Float64) -> Bool:
    var sign=Float64(1) if cross2(polygon[0],polygon[1],polygon[2])>=0 else -1.0
    for i in range(4):
        var a=polygon[i];var b=polygon[(i+1)%4]
        var bound=resolution*(1+abs(b.x-a.x)+abs(b.y-a.y))
        if sign*cross2(a,b,p)<-bound:return False
    return True

def hull(points: List[P2],resolution: Float64) -> List[P2]:
    var sorted=points.copy()
    for i in range(len(sorted)):
        for j in range(i+1,len(sorted)):
            if sorted[j].x<sorted[i].x or (sorted[j].x==sorted[i].x and sorted[j].y<sorted[i].y):
                var p=sorted[i];sorted[i]=sorted[j];sorted[j]=p
    var unique=List[P2]()
    for p in sorted:
        var duplicate=False
        for q in unique:
            if abs(p.x-q.x)<=resolution and abs(p.y-q.y)<=resolution:duplicate=True
        if not duplicate:unique.append(p)
    if len(unique)<=2:return unique^
    var boundary=List[P2]()
    for leg in range(2):
        var base=len(boundary)
        for k in range(len(unique)):
            var p=unique[k] if leg==0 else unique[len(unique)-1-k]
            while len(boundary)>=base+2:
                var a=boundary[len(boundary)-2];var b=boundary[len(boundary)-1]
                var band=resolution*(1+abs(b.x-a.x)+abs(b.y-a.y)+abs(p.x-a.x)+abs(p.y-a.y))
                if cross2(a,b,p)>band:break
                _=boundary.pop()
            boundary.append(p)
        _=boundary.pop()
    return boundary^

@fieldwise_init
struct ReferencePoint(ImplicitlyCopyable,Movable):
    var a: Vec3
    var b: Vec3
    var separation: Float64

def reference_patch(a: ReferenceBox,b: ReferenceBox,code: Int,resolution: Float64) -> List[ReferencePoint]:
    var reverse=code>=3;var axis=code-3 if reverse else code;var r=b if reverse else a;var inc=a if reverse else b
    var n=face(r,axis);var toward=inc.center-r.center
    if scalar_dot(toward,n)<0:n=n*(-1)
    var rcenter=r.center-a.center+r.edge(axis)*(1.0 if scalar_dot(n,r.edge(axis))>=0 else -1.0)
    var ia=0;var alignment=abs(scalar_dot(n,face(inc,0)))
    for i in range(1,3):
        var d=abs(scalar_dot(n,face(inc,i)))
        if d>alignment:alignment=d;ia=i
    var icenter=inc.center-a.center+inc.edge(ia)*(-1.0 if scalar_dot(n,inc.edge(ia))>=0 else 1.0)
    var inormal=face(inc,ia);var denominator=scalar_dot(inormal,n)
    var u=direction(r.edge((axis+1)%3));var v=direction(scalar_cross(n,u))
    var rpoly=Array[P2,4](fill=P2(0,0));var ipoly=Array[P2,4](fill=P2(0,0))
    for i in range(4):
        var sx=1.0 if i==0 or i==3 else -1.0;var sy=1.0 if i<2 else -1.0
        var rv=r.edge((axis+1)%3)*sx+r.edge((axis+2)%3)*sy
        var iv=icenter+inc.edge((ia+1)%3)*sx+inc.edge((ia+2)%3)*sy-rcenter
        rpoly[i]=P2(scalar_dot(rv,u),scalar_dot(rv,v));ipoly[i]=P2(scalar_dot(iv,u),scalar_dot(iv,v))
    var candidates=List[P2]()
    for p in rpoly:
        var rp=rcenter+u*p.x+v*p.y;var depth=-scalar_dot(inormal,rp-icenter)/denominator
        if inside(p,ipoly,resolution) and depth<=resolution:candidates.append(p)
    for p in ipoly:
        var rp=rcenter+u*p.x+v*p.y;var depth=-scalar_dot(inormal,rp-icenter)/denominator
        if inside(p,rpoly,resolution) and depth<=resolution:candidates.append(p)
    for i in range(4):
        var p=rpoly[i];var q=rpoly[(i+1)%4]
        for j in range(4):
            var t=ipoly[j];var w=ipoly[(j+1)%4]
            var dx=q.x-p.x;var dy=q.y-p.y;var ex=w.x-t.x;var ey=w.y-t.y;var determinant=dx*ey-dy*ex
            if determinant==0:continue
            var alpha=((t.x-p.x)*ey-(t.y-p.y)*ex)/determinant
            var beta=((t.x-p.x)*dy-(t.y-p.y)*dx)/determinant
            if alpha<0 or alpha>1 or beta<0 or beta>1:continue
            var point=P2(p.x+alpha*dx,p.y+alpha*dy);var rp=rcenter+u*point.x+v*point.y
            if -scalar_dot(inormal,rp-icenter)/denominator<=resolution:candidates.append(point)
    # Enumerate contact-plane crossings separately from quad/quad edge crossings.
    for which in [0,1]:
        var poly=rpoly.copy() if which==0 else ipoly.copy()
        for i in range(4):
            var p=poly[i];var q=poly[(i+1)%4]
            var d0=-scalar_dot(inormal,rcenter+u*p.x+v*p.y-icenter)/denominator
            var d1=-scalar_dot(inormal,rcenter+u*q.x+v*q.y-icenter)/denominator
            if (d0<0 and d1>0) or (d0>0 and d1<0):
                var alpha=d0/(d0-d1);var point=P2(p.x+(q.x-p.x)*alpha,p.y+(q.y-p.y)*alpha)
                if inside(point,rpoly,resolution) and inside(point,ipoly,resolution):candidates.append(point)
    var polygon=hull(candidates,resolution);var result=List[ReferencePoint]()
    for p in polygon:
        var reference=rcenter+u*p.x+v*p.y;var sep=-scalar_dot(inormal,reference-icenter)/denominator;var incident=reference+n*sep
        result.append(ReferencePoint(incident if reverse else reference,reference if reverse else incident,sep))
    return result^

def reference_edge(a: ReferenceBox,b: ReferenceBox,code: Int) -> ReferencePoint:
    # Enumerate support edges from corners, then solve their closest points
    # using a scalar 2x2 Gram system (GPU uses transverse projection).
    var ia=(code-6)//3;var ib=(code-6)%3
    var n=direction(scalar_cross(a.edge(ia),b.edge(ib)))
    if scalar_dot(b.center-a.center,n)<0:n=n*(-1)
    var pa=Vec3(0,0,0);var pb=Vec3(0,0,0);var ba=Float64(-1e300);var bb=Float64(1e300)
    for mask in range(8):
        if (mask&(1<<ia))==0:
            var corner=a.vertex(mask,a.center);var projection=scalar_dot(corner,n)
            if projection>ba:ba=projection;pa=corner
        if (mask&(1<<ib))==0:
            var corner=b.vertex(mask,a.center);var projection=scalar_dot(corner,n)
            if projection<bb:bb=projection;pb=corner
    var u=a.edge(ia)*2;var v=b.edge(ib)*2;var w=pa-pb
    var aa=scalar_dot(u,u);var ab=scalar_dot(u,v);var bv=scalar_dot(v,v);var du=scalar_dot(u,w);var dv=scalar_dot(v,w)
    var denominator=aa*bv-ab*ab;var s=(ab*dv-bv*du)/denominator;var t=(aa*dv-ab*du)/denominator
    s=max(0.0,min(1.0,s));t=max(0.0,min(1.0,t));var wa=pa+u*s;var wb=pb+v*t
    return ReferencePoint(wa,wb,scalar_dot(wb-wa,n))
