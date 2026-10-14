"""Independent CPU sphere oracle: quaternion matrix and scalar brute-force math.

Does not call the GPU bounds/contact helpers or consume their calculated centers.
Shared result types carry identities only. No collision response.
"""
from std.collections import List,Array
from std.math import sqrt
from mojo_game import RigidBody3D,Vec3
from .lifecycle import BodyHandle
from .collision import ShapeHandle,PairKey,SphereContact,DetectionFrame

@fieldwise_init
struct OracleSphere(ImplicitlyCopyable,Movable):
    var shape: ShapeHandle
    var body_handle: BodyHandle
    var revision: UInt64
    var body: RigidBody3D
    var radius: Float64
    var offset: Vec3

def oracle_center(s: OracleSphere) -> Vec3:
    var q=s.body.orientation
    var length=sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w)
    var x=q.x/length;var y=q.y/length;var z=q.z/length;var w=q.w/length
    var o=s.offset
    return Vec3(s.body.position.x+(1-2*(y*y+z*z))*o.x+2*(x*y-z*w)*o.y+2*(x*z+y*w)*o.z,
        s.body.position.y+2*(x*y+z*w)*o.x+(1-2*(x*x+z*z))*o.y+2*(y*z-x*w)*o.z,
        s.body.position.z+2*(x*z-y*w)*o.x+2*(y*z+x*w)*o.y+(1-2*(x*x+y*y))*o.z)

def oracle_frame(spheres: List[OracleSphere]) -> DetectionFrame:
    var by_slot=Array[Int,64](fill=-1)
    for i in range(len(spheres)):by_slot[Int(spheres[i].shape.slot)]=i
    var pairs=List[PairKey]();var hits=List[SphereContact]()
    for i in range(64):
        if by_slot[i]<0:continue
        var a=spheres[by_slot[i]];var ca=oracle_center(a)
        for j in range(i+1,64):
            if by_slot[j]<0:continue
            var b=spheres[by_slot[j]];var cb=oracle_center(b)
            if ca.x-a.radius>cb.x+b.radius or cb.x-b.radius>ca.x+a.radius:continue
            if ca.y-a.radius>cb.y+b.radius or cb.y-b.radius>ca.y+a.radius:continue
            if ca.z-a.radius>cb.z+b.radius or cb.z-b.radius>ca.z+a.radius:continue
            var key=PairKey(a.shape,b.shape,a.revision,b.revision,a.body_handle,b.body_handle)
            pairs.append(key)
            var dx=cb.x-ca.x;var dy=cb.y-ca.y;var dz=cb.z-ca.z
            var distance=sqrt(dx*dx+dy*dy+dz*dz)
            var separation=distance-(a.radius+b.radius)
            if separation>0:continue
            var normal=Vec3(1,0,0) if distance==0 else Vec3(dx/distance,dy/distance,dz/distance)
            var wa=Vec3(ca.x+normal.x*a.radius,ca.y+normal.y*a.radius,ca.z+normal.z*a.radius)
            var wb=Vec3(cb.x-normal.x*b.radius,cb.y-normal.y*b.radius,cb.z-normal.z*b.radius)
            hits.append(SphereContact(key,normal,separation,wa,wb))
    return DetectionFrame(pairs^,hits^,0)
