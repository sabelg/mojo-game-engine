"""Independent CPU friction: spectral disk solve, different basis, KKT stopping."""
from std.collections import List,Array
from std.math import isfinite,sqrt
from mojo_game import RigidBody3D,Vec3
from .contact_oracle import OracleSphere
from .box_oracle import OracleBox,mixed_frame,matrix,apply
from .normal_response import ResponseReport
from .friction_response import FrictionReport
from .response_reference import ResponseReference,ReferenceResult

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


def relative(a: RigidBody3D,b: RigidBody3D,p: Vec3) -> Vec3:
    return b.linear_velocity+b.angular_velocity.cross(p-b.position)-a.linear_velocity-a.angular_velocity.cross(p-a.position)
def push(mut a: RigidBody3D,mut b: RigidBody3D,p: Vec3,j: Vec3):
    if a.properties.mass>0:
        a.linear_velocity=a.linear_velocity-j*inv_mass(a);a.angular_velocity=a.angular_velocity-inverse_tensor(a,(p-a.position).cross(j))
    if b.properties.mass>0:
        b.linear_velocity=b.linear_velocity+j*inv_mass(b);b.angular_velocity=b.angular_velocity+inverse_tensor(b,(p-b.position).cross(j))
def delta_velocity(a: RigidBody3D,b: RigidBody3D,p: Vec3,j: Vec3) -> Vec3:
    var ca=a;var cb=b;push(ca,cb,p,j);return relative(ca,cb,p)-relative(a,b,p)
def cpu_basis(n: Vec3) -> Tuple[Vec3,Vec3]:
    var axis=Vec3(0,0,1) if abs(n.z)<.8 else Vec3(1,0,0)
    var t=axis-n*axis.dot(n);t=t*(1/t.length());return t,n.cross(t)
def spectral_min(k: Vec3,u: Vec3,radius: Float64) -> Vec3:
    if radius==0:return Vec3(0,0,0)
    var large=(k.x+k.z+sqrt((k.x-k.z)*(k.x-k.z)+4*k.y*k.y))*.5
    var small=(k.x*k.z-k.y*k.y)/large
    var ex=Float64(1);var ey=Float64(0)
    if k.y!=0:
        ex=k.y;ey=large-k.x;var length=sqrt(ex*ex+ey*ey);ex/=length;ey/=length
    elif k.z>k.x:ex=0;ey=1
    var a=u.x*ex+u.y*ey;var b=-u.x*ey+u.y*ex
    var x=-a/large;var y=-b/small;var eta=Float64(0)
    if sqrt(x*x+y*y)>radius:
        var low=Float64(0);var high=max(large,Float64(1))
        for _ in range(100):
            if sqrt((a/(large+high))**2+(b/(small+high))**2)<=radius:break
            high*=2
        for _ in range(80):
            var middle=(low+high)*.5
            if sqrt((a/(large+middle))**2+(b/(small+middle))**2)>radius:low=middle
            else:high=middle
        eta=high;x=-a/(large+eta);y=-b/(small+eta)
    return Vec3(ex*x-ey*y,ey*x+ex*y,eta)

@fieldwise_init
struct FrictionResult(Movable):
    var bodies: List[RigidBody3D]
    var slots: List[Int]
    var report: FrictionReport
    var normal_impulses: List[Float64]
    var tangent_impulses: List[Vec3]

struct FrictionReference(Movable):
    var last_error: Int32
    var capacity: Int
    def __init__(out self,capacity: Int=64):
        self.capacity=capacity;self.last_error=0
    def fail(mut self,code: Int32) raises:
        self.last_error=code;raise Error("CPU response reference rejected; code="+String(code))

    def solve(mut self,spheres: List[OracleSphere],boxes: List[OracleBox],dt: Float64,e: Float64,vi: Int=32,pi: Int=32,mu: Float64=0) raises -> FrictionResult:
        self.last_error=0
        if not isfinite(mu) or mu<0 or mu>2:self.fail(62)
        if mu==0:
            var normal=ResponseReference(self.capacity);var result: ReferenceResult
            try:result=normal.solve(spheres,boxes,dt,e,vi,pi)
            except error:
                self.last_error=normal.last_error
                raise error
            return FrictionResult(result.bodies.copy(),result.slots.copy(),FrictionReport(result.report,mu,0,0,0,0),List[Float64](),List[Vec3]())
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
        var tangents=List[Vec3]();var tangent_tolerance=Float64(1e-9)
        for i in range(count):
            tangents.append(Vec3(0,0,0));var c=frame.contacts[i]
            var rel=relative(bodies[lookup[Int(c.key.body_a.slot)]],bodies[lookup[Int(c.key.body_b.slot)]],points[i]);var vt=rel-c.normal*rel.dot(c.normal)
            tangent_tolerance=max(tangent_tolerance,1e-9*(1+vt.length()))
        var friction_residual=Float64(0);var maximum_impulse=Float64(0);var cone_excess=Float64(0);var sliding=Int32(0)
        var before=Float64(0)
        for i in range(len(bodies)):
            if touched[i]:before+=energy(bodies[i])
        var converged=count==0;var velocity_used=Int(0);var residual=Float64(0)
        for sweep in range(vi):
            if converged:break
            for i in range(count):
                if effective[i]==0:continue
                var c=frame.contacts[i];var ia=lookup[Int(c.key.body_a.slot)];var ib=lookup[Int(c.key.body_b.slot)];var a=bodies[ia];var b=bodies[ib];var p=points[i]
                var next=max(0.0,impulses[i]+(targets[i]-point_speed(a,b,p,c.normal))/effective[i])
                if not isfinite(next) or next>1e4:self.fail(61)
                push(a,b,p,c.normal*(next-impulses[i]));impulses[i]=next
                # Remove old tangential contribution explicitly on body copies.
                var free_a=a;var free_b=b;push(free_a,free_b,p,tangents[i]*(-1))
                var basis=cpu_basis(c.normal);var t=basis[0];var v=basis[1]
                var response_t=delta_velocity(a,b,p,t);var response_v=delta_velocity(a,b,p,v)
                var metric=Vec3(t.dot(response_t),t.dot(response_v),v.dot(response_v));var free=relative(free_a,free_b,p)
                var optimum=spectral_min(metric,Vec3(free.dot(t),free.dot(v),0),mu*next)
                var jt=t*optimum.x+v*optimum.y;push(a,b,p,jt-tangents[i]);tangents[i]=jt
                if not profile(a) or not profile(b):self.fail(52)
                bodies[ia]=a;bodies[ib]=b
            residual=0;friction_residual=0;maximum_impulse=0;cone_excess=0;sliding=0
            for i in range(count):
                if effective[i]==0:continue
                var c=frame.contacts[i];var a=bodies[lookup[Int(c.key.body_a.slot)]];var b=bodies[lookup[Int(c.key.body_b.slot)]]
                var rel=relative(a,b,points[i]);var error=rel.dot(c.normal)-targets[i]
                residual=max(residual,abs(error) if impulses[i]>0 else max(0.0,-error))
                var vt=rel-c.normal*rel.dot(c.normal);var radius=mu*impulses[i];var length=tangents[i].length()
                maximum_impulse=max(maximum_impulse,length);cone_excess=max(cone_excess,max(0.0,length-radius))
                if length>radius+1e-12*(1+radius):self.fail(64)
                if radius>0:
                    if length<radius*(1-1e-12):friction_residual=max(friction_residual,vt.length())
                    else:
                        var eta=max(0.0,-vt.dot(tangents[i])/(length*length))
                        friction_residual=max(friction_residual,(vt+tangents[i]*eta).length())
                        if eta>0:sliding+=1
            velocity_used=sweep+1;converged=residual<=tolerance and friction_residual<=tangent_tolerance
        if not converged:self.fail(Int32(55 if residual>tolerance else 63))
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
        return FrictionResult(bodies^,slots^,FrictionReport(ResponseReport(Int32(count),Int32(fixed_pairs),Int32(velocity_used),Int32(position_used),before,after,residual,penetration,max_shift),mu,friction_residual,maximum_impulse,cone_excess,sliding),impulses^,tangents^)
