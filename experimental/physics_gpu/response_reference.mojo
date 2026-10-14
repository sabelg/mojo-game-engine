"""Independent scalar/matrix CPU normal-response reference over CPU geometry.

No GPU inverse-inertia, impulse, stopping or projection helper is called.
"""
from std.collections import List,Array
from std.math import isfinite
from mojo_game import RigidBody3D,Vec3
from .contact_oracle import OracleSphere
from .box_oracle import OracleBox,mixed_frame,matrix,apply
from .normal_response import ResponseReport

def inverse_tensor(b: RigidBody3D,v: Vec3) -> Vec3:
    if b.properties.mass==0:return Vec3(0,0,0)
    var r=matrix(b.orientation)
    var local=Vec3(r[0]*v.x+r[3]*v.y+r[6]*v.z,r[1]*v.x+r[4]*v.y+r[7]*v.z,r[2]*v.x+r[5]*v.y+r[8]*v.z)
    var inertia=b.properties.inertia
    return apply(r,Vec3(local.x/inertia.x,local.y/inertia.y,local.z/inertia.z))
def energy(b: RigidBody3D) -> Float64:
    if b.properties.mass==0:return 0
    var r=matrix(b.orientation);var w=b.angular_velocity
    var local=Vec3(r[0]*w.x+r[3]*w.y+r[6]*w.z,r[1]*w.x+r[4]*w.y+r[7]*w.z,r[2]*w.x+r[5]*w.y+r[8]*w.z)
    return .5*(b.properties.mass*b.linear_velocity.dot(b.linear_velocity)+b.properties.inertia.x*local.x*local.x+b.properties.inertia.y*local.y*local.y+b.properties.inertia.z*local.z*local.z)
def inv_mass(b: RigidBody3D) -> Float64:
    return 0.0 if b.properties.mass==0 else 1/b.properties.mass
def point_speed(a: RigidBody3D,b: RigidBody3D,p: Vec3,n: Vec3) -> Float64:
    var va=a.linear_velocity+a.angular_velocity.cross(p-a.position)
    var vb=b.linear_velocity+b.angular_velocity.cross(p-b.position)
    return (vb-va).dot(n)
def maximum(v: Vec3) -> Float64:
    return max(abs(v.x),max(abs(v.y),abs(v.z)))
def profile(b: RigidBody3D) -> Bool:
    if maximum(b.position)>1000 or maximum(b.linear_velocity)>20 or maximum(b.angular_velocity)>10:return False
    var q=b.orientation
    if abs(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w-1)>1e-10:return False
    if b.properties.mass==0:return True
    var d=b.properties.inertia
    return b.properties.mass>=.1 and b.properties.mass<=100 and min(d.x,min(d.y,d.z))>=1e-4 and maximum(d)<=1000

@fieldwise_init
struct ReferenceResult(Movable):
    var bodies: List[RigidBody3D]
    var slots: List[Int]
    var report: ResponseReport

struct ResponseReference(Movable):
    var last_error: Int32
    var capacity: Int
    def __init__(out self,capacity: Int=64):
        self.capacity=capacity;self.last_error=0
    def fail(mut self,code: Int32) raises:
        self.last_error=code;raise Error("CPU response reference rejected; code="+String(code))

    def solve(mut self,spheres: List[OracleSphere],boxes: List[OracleBox],dt: Float64,e: Float64,vi: Int=32,pi: Int=32) raises -> ReferenceResult:
        self.last_error=0
        var frame=mixed_frame(spheres,boxes);var count=len(frame.contacts)
        if count>self.capacity:self.fail(50)
        if not isfinite(dt) or dt<1.0/240 or dt>1.0/30 or not isfinite(e) or e<0 or e>1 or vi<1 or vi>64 or pi<1 or pi>64:self.fail(51)
        var bodies=List[RigidBody3D]();var slots=List[Int]();var lookup=Array[Int,256](fill=-1)
        for slot in range(256):
            for s in spheres:
                if Int(s.body_handle.slot)==slot:
                    lookup[slot]=len(bodies);bodies.append(s.body);slots.append(slot)
                    if s.radius<.05 or s.radius>10 or maximum(s.offset)>10:self.fail(52)
            for b in boxes:
                if Int(b.body_handle.slot)==slot:
                    lookup[slot]=len(bodies);bodies.append(b.body);slots.append(slot)
                    if min(b.half_extents.x,min(b.half_extents.y,b.half_extents.z))<.05 or maximum(b.half_extents)>10 or maximum(b.offset)>10:self.fail(52)
        var original=List[RigidBody3D]();var touched=List[Bool]()
        for b in bodies:
            b.validate()
            if not profile(b):self.fail(52)
            original.append(b);touched.append(False)
        var impulses=List[Float64]();var position_impulses=List[Float64]();var targets=List[Float64]();var effective=List[Float64]();var points=List[Vec3]();var fixed_pairs=Int(0);var tolerance=Float64(1e-9)
        for c in frame.contacts:
            var ia=lookup[Int(c.key.body_a.slot)];var ib=lookup[Int(c.key.body_b.slot)];var a=bodies[ia];var b=bodies[ib]
            var p=c.witness_a*.5+c.witness_b*.5;points.append(p);impulses.append(0);position_impulses.append(0)
            if a.properties.mass==0 and b.properties.mass==0:
                targets.append(0);effective.append(0);fixed_pairs+=1;continue
            if -c.separation>.25:self.fail(57)
            var ra=(p-a.position).cross(c.normal);var rb=(p-b.position).cross(c.normal)
            var k=inv_mass(a)+inv_mass(b)+ra.dot(inverse_tensor(a,ra))+rb.dot(inverse_tensor(b,rb))
            var initial=point_speed(a,b,p,c.normal);targets.append(-e*initial if initial<-.2 else 0);effective.append(k)
            tolerance=max(tolerance,1e-9*(1+abs(initial)));touched[ia]=True;touched[ib]=True
        var before=Float64(0)
        for i in range(len(bodies)):
            if touched[i]:before+=energy(bodies[i])
        var converged=count==0;var velocity_used=Int(0);var residual=Float64(0)
        for sweep in range(vi):
            if converged:break
            for i in range(count):
                if effective[i]==0:continue
                var c=frame.contacts[i];var ia=lookup[Int(c.key.body_a.slot)];var ib=lookup[Int(c.key.body_b.slot)];var a=bodies[ia];var b=bodies[ib];var p=points[i]
                var next=max(0.0,impulses[i]+(targets[i]-point_speed(a,b,p,c.normal))/effective[i]);var j=c.normal*(next-impulses[i])
                if not isfinite(next) or next>1e4:self.fail(61)
                if a.properties.mass>0:
                    a.linear_velocity=a.linear_velocity-j*inv_mass(a);a.angular_velocity=a.angular_velocity-inverse_tensor(a,(p-a.position).cross(j))
                if b.properties.mass>0:
                    b.linear_velocity=b.linear_velocity+j*inv_mass(b);b.angular_velocity=b.angular_velocity+inverse_tensor(b,(p-b.position).cross(j))
                if not profile(a) or not profile(b):self.fail(52)
                bodies[ia]=a;bodies[ib]=b;impulses[i]=next
            residual=0
            for i in range(count):
                if effective[i]==0:continue
                var c=frame.contacts[i];var error=point_speed(bodies[lookup[Int(c.key.body_a.slot)]],bodies[lookup[Int(c.key.body_b.slot)]],points[i],c.normal)-targets[i]
                residual=max(residual,abs(error) if impulses[i]>0 else max(0.0,-error))
            velocity_used=sweep+1;converged=residual<=tolerance
        if not converged:self.fail(55)
        var after=Float64(0)
        for i in range(len(bodies)):
            if touched[i]:after+=energy(bodies[i])
        if after>before+1e-9*(1+before):self.fail(56)
        converged=count==0;var position_used=Int(0);var max_shift=Float64(0)
        for sweep in range(pi):
            if converged:break
            for i in range(count):
                if effective[i]==0:continue
                var c=frame.contacts[i];var ia=lookup[Int(c.key.body_a.slot)];var ib=lookup[Int(c.key.body_b.slot)];var a=bodies[ia];var b=bodies[ib]
                var separation=c.separation+c.normal.dot((b.position-original[ib].position)-(a.position-original[ia].position))
                var next=max(0.0,position_impulses[i]-(separation+1e-5)/(inv_mass(a)+inv_mass(b)));var correction=c.normal*(next-position_impulses[i])
                if a.properties.mass>0:a.position=a.position-correction*inv_mass(a)
                if b.properties.mass>0:b.position=b.position+correction*inv_mass(b)
                max_shift=max(max_shift,max((a.position-original[ia].position).length(),(b.position-original[ib].position).length()))
                if max_shift>.25:self.fail(59)
                if not profile(a) or not profile(b):self.fail(52)
                bodies[ia]=a;bodies[ib]=b;position_impulses[i]=next
            var position_residual=Float64(0)
            for i in range(count):
                if effective[i]==0:continue
                var c=frame.contacts[i];var ia=lookup[Int(c.key.body_a.slot)];var ib=lookup[Int(c.key.body_b.slot)]
                var error=c.separation+c.normal.dot((bodies[ib].position-original[ib].position)-(bodies[ia].position-original[ia].position))+1e-5
                position_residual=max(position_residual,abs(error) if position_impulses[i]>0 else max(0.0,-error))
            position_used=sweep+1;converged=position_residual<=1e-9
        if not converged:self.fail(58)
        var new_spheres=List[OracleSphere]();var new_boxes=List[OracleBox]()
        for s in spheres:
            var copy=s;copy.body=bodies[lookup[Int(s.body_handle.slot)]];new_spheres.append(copy)
        for b in boxes:
            var copy=b;copy.body=bodies[lookup[Int(b.body_handle.slot)]];new_boxes.append(copy)
        var post=mixed_frame(new_spheres,new_boxes);var penetration=Float64(0)
        if len(post.contacts)>self.capacity:self.fail(60)
        for c in post.contacts:
            var a=bodies[lookup[Int(c.key.body_a.slot)]];var b=bodies[lookup[Int(c.key.body_b.slot)]]
            if a.properties.mass==0 and b.properties.mass==0:continue
            penetration=max(penetration,max(0.0,-c.separation))
            if c.separation < -1e-5-1e-9 or point_speed(a,b,c.witness_a*.5+c.witness_b*.5,c.normal)<-tolerance:self.fail(60)
        return ReferenceResult(bodies^,slots^,ResponseReport(Int32(count),Int32(fixed_pairs),Int32(velocity_used),Int32(position_used),before,after,residual,penetration,max_shift))
