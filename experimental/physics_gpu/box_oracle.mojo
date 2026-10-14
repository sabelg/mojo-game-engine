"""Independent CPU OBB oracle: composed matrices, eight corners, six faces.

No GPU bounds, quaternion-product, clamp-vector or contact helper is reused.
"""
from std.collections import List,Array
from std.math import sqrt
from mojo_game import Vec3,Quaternion,RigidBody3D
from .lifecycle import BodyHandle
from .collision import ShapeHandle,PairKey,SphereContact,DetectionFrame
from .contact_oracle import OracleSphere,oracle_center

@fieldwise_init
struct OracleBox(ImplicitlyCopyable,Movable):
    var shape: ShapeHandle
    var body_handle: BodyHandle
    var revision: UInt64
    var body: RigidBody3D
    var half_extents: Vec3
    var offset: Vec3
    var orientation: Quaternion

def scalar(v: Vec3,axis: Int) -> Float64:
    return v.x if axis==0 else v.y if axis==1 else v.z

def matrix(q: Quaternion) -> Array[Float64,9]:
    # Rational quaternion matrix after max-component scaling. Avoid normalizing
    # each component with sqrt before squaring: that introduces orthogonality
    # drift even for exact signed quarter-turn/inverse constructions.
    var scale=max(max(abs(q.x),abs(q.y)),max(abs(q.z),abs(q.w)))
    var x=q.x/scale;var y=q.y/scale;var z=q.z/scale;var w=q.w/scale
    var norm=x*x+y*y+z*z+w*w
    var result=Array[Float64,9](fill=0)
    result[0]=(w*w+x*x-y*y-z*z)/norm;result[1]=2*(x*y-z*w)/norm;result[2]=2*(x*z+y*w)/norm
    result[3]=2*(x*y+z*w)/norm;result[4]=(w*w-x*x+y*y-z*z)/norm;result[5]=2*(y*z-x*w)/norm
    result[6]=2*(x*z-y*w)/norm;result[7]=2*(y*z+x*w)/norm;result[8]=(w*w-x*x-y*y+z*z)/norm
    return result^

def apply(m: Array[Float64,9],v: Vec3) -> Vec3:
    return Vec3(m[0]*v.x+m[1]*v.y+m[2]*v.z,m[3]*v.x+m[4]*v.y+m[5]*v.z,m[6]*v.x+m[7]*v.y+m[8]*v.z)

def box_axes(b: OracleBox) -> Array[Vec3,3]:
    var outer=matrix(b.body.orientation);var inner=matrix(b.orientation)
    var result=Array[Vec3,3](fill=Vec3(0,0,0))
    result[0]=apply(outer,apply(inner,Vec3(1,0,0)));result[1]=apply(outer,apply(inner,Vec3(0,1,0)));result[2]=apply(outer,apply(inner,Vec3(0,0,1)))
    return result^

def box_center(b: OracleBox) -> Vec3:
    return b.body.position+apply(matrix(b.body.orientation),b.offset)

def box_corners_bounds(b: OracleBox) -> Tuple[Vec3,Vec3]:
    var center=box_center(b);var axes=box_axes(b)
    var low=Vec3(1e30,1e30,1e30);var high=Vec3(-1e30,-1e30,-1e30)
    for bits in range(8):
        var p=center+axes[0]*(b.half_extents.x*(1.0 if bits&1 else -1.0))+axes[1]*(b.half_extents.y*(1.0 if bits&2 else -1.0))+axes[2]*(b.half_extents.z*(1.0 if bits&4 else -1.0))
        low=Vec3(min(low.x,p.x),min(low.y,p.y),min(low.z,p.z));high=Vec3(max(high.x,p.x),max(high.y,p.y),max(high.z,p.z))
    return low,high

def oracle_box_contact(s: OracleSphere,b: OracleBox) -> SphereContact:
    var center=oracle_center(s);var origin=box_center(b);var axes=box_axes(b);var d=center-origin
    var u=Array[Float64,3](fill=0);u[0]=d.dot(axes[0]);u[1]=d.dot(axes[1]);u[2]=d.dot(axes[2])
    var half=Array[Float64,3](fill=0);half[0]=b.half_extents.x;half[1]=b.half_extents.y;half[2]=b.half_extents.z
    var inside=True
    for i in range(3):
        if u[i]<-half[i] or u[i]>half[i]:inside=False
    var best=Float64(1e30);var closest=origin;var outward=Vec3(1,0,0)
    # Enumerate six rectangular faces, rather than GPU's all-axis clamp and
    # inside-clearance branch. Order +X,-X,+Y,-Y,+Z,-Z resolves exact ties.
    for face in range(6):
        var axis=face//2;var sign=Float64(1 if face%2==0 else -1)
        var score=Float64(0);var point=origin
        for j in range(3):
            var coordinate=sign*half[j] if j==axis else max(-half[j],min(half[j],u[j]))
            var difference=coordinate-u[j];score+=difference*difference
            point=point+axes[j]*coordinate
        if score<best:best=score;closest=point;outward=axes[axis]*sign
    var distance=sqrt(best)
    var normal=outward*(-1) if inside else (closest-center)*(1/distance)
    var separation=-(distance+s.radius) if inside else distance-s.radius
    var key=PairKey(s.shape,b.shape,s.revision,b.revision,s.body_handle,b.body_handle)
    var wa=center+normal*s.radius;var wb=closest
    if b.shape.slot<s.shape.slot:
        key=PairKey(b.shape,s.shape,b.revision,s.revision,b.body_handle,s.body_handle)
        normal=normal*(-1);var swap=wa;wa=wb;wb=swap
    return SphereContact(key,normal,separation,wa,wb)

def mixed_frame(spheres: List[OracleSphere],boxes: List[OracleBox]) -> DetectionFrame:
    var si=Array[Int,64](fill=-1);var bi=Array[Int,64](fill=-1)
    for i in range(len(spheres)):si[Int(spheres[i].shape.slot)]=i
    for i in range(len(boxes)):bi[Int(boxes[i].shape.slot)]=i
    var pairs=List[PairKey]();var hits=List[SphereContact]()
    for a in range(64):
        for b in range(a+1,64):
            if si[a]>=0 and si[b]>=0:
                var aa=spheres[si[a]];var bb=spheres[si[b]];var ca=oracle_center(aa);var cb=oracle_center(bb)
                if abs(ca.x-cb.x)>aa.radius+bb.radius or abs(ca.y-cb.y)>aa.radius+bb.radius or abs(ca.z-cb.z)>aa.radius+bb.radius:continue
                var key=PairKey(aa.shape,bb.shape,aa.revision,bb.revision,aa.body_handle,bb.body_handle);pairs.append(key)
                var d=cb-ca;var length=sqrt(d.x*d.x+d.y*d.y+d.z*d.z);var separation=length-(aa.radius+bb.radius)
                if separation>0:continue
                var normal=Vec3(1,0,0) if length==0 else d*(1/length)
                hits.append(SphereContact(key,normal,separation,ca+normal*aa.radius,cb-normal*bb.radius))
            elif (si[a]>=0 and bi[b]>=0) or (bi[a]>=0 and si[b]>=0):
                var sphere=spheres[si[a] if si[a]>=0 else si[b]];var box=boxes[bi[a] if bi[a]>=0 else bi[b]]
                var center=oracle_center(sphere);var bounds=box_corners_bounds(box)
                if center.x-sphere.radius>bounds[1].x or center.x+sphere.radius<bounds[0].x or center.y-sphere.radius>bounds[1].y or center.y+sphere.radius<bounds[0].y or center.z-sphere.radius>bounds[1].z or center.z+sphere.radius<bounds[0].z:continue
                var contact=oracle_box_contact(sphere,box);pairs.append(contact.key)
                if contact.separation<=0:hits.append(contact)
            # Unsupported box/box pairs are deliberately absent, even if their
            # AABBs overlap. Completeness applies only to the declared pair set.
    return DetectionFrame(pairs^,hits^,0)
