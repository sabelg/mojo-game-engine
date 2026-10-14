"""Independent geometry, unit-response, spectral and complete-pivot coupled replay."""
from std.collections import Array
from std.math import sqrt
from mojo_game import Vec3

# This uses row elimination plus a null-space least-norm projection. It does not
# call the GPU Jacobi eigensolver or production impulse/selection helpers.
def reference_linear(k: Array[Float64,16],q: Array[Float64,4],mask: Int) -> Array[Float64,4]:
    var a=Array[Float64,20](fill=0);var pivots=Array[Int,4](fill=-1);var rank=0;var scale=Float64(0)
    for i in range(4):
        for j in range(4):
            if (mask&(1<<i))!=0 and (mask&(1<<j))!=0:a[i*5+j]=k[i*4+j];scale=max(scale,abs(a[i*5+j]))
        if (mask&(1<<i))!=0:a[i*5+4]=-q[i]
    for col in range(4):
        var row=rank;var best=Float64(0)
        for i in range(rank,4):
            if abs(a[i*5+col])>best:best=abs(a[i*5+col]);row=i
        if best<=1e-13*max(1e-30,scale):continue
        for j in range(5):var saved=a[rank*5+j];a[rank*5+j]=a[row*5+j];a[row*5+j]=saved
        var pivot=a[rank*5+col]
        for j in range(5):a[rank*5+j]/=pivot
        for i in range(4):
            if i==rank:continue
            var factor=a[i*5+col]
            for j in range(5):a[i*5+j]-=factor*a[rank*5+j]
        pivots[rank]=col;rank+=1
    var result=Array[Float64,4](fill=0)
    for i in range(rank):result[pivots[i]]=a[i*5+4]
    # Orthogonalize a null-space basis with modified Gram-Schmidt, then remove
    # its component from the particular solution. Inactive coordinates stay 0.
    var nulls=Array[Float64,16](fill=0);var count=0
    for col in range(4):
        if (mask&(1<<col))==0:continue
        var pivot=False
        for i in range(rank):
            if pivots[i]==col:pivot=True
        if pivot:continue
        var v=Array[Float64,4](fill=0);v[col]=1
        for i in range(rank):v[pivots[i]]=-a[i*5+col]
        for basis in range(count):
            var dot=Float64(0)
            for j in range(4):dot+=v[j]*nulls[basis*4+j]
            for j in range(4):v[j]-=dot*nulls[basis*4+j]
        var length=Float64(0)
        for j in range(4):length+=v[j]*v[j]
        length=sqrt(length)
        for j in range(4):nulls[count*4+j]=v[j]/length
        count+=1
    for basis in range(count):
        var dot=Float64(0)
        for j in range(4):dot+=result[j]*nulls[basis*4+j]
        for j in range(4):result[j]-=dot*nulls[basis*4+j]
    return result^

def reference_block(k: Array[Float64,16],q: Array[Float64,4],count: Int) -> Array[Float64,4]:
    var answer=Array[Float64,4](fill=0);var least=Float64(1e300)
    for mask in range(1<<count):
        var x=reference_linear(k,q,mask);var valid=True;var length=Float64(0)
        for i in range(count):
            if x[i]<-1e-10:valid=False
            x[i]=max(0.0,x[i]);length+=x[i]*x[i]
        for i in range(count):
            var residual=q[i]
            for j in range(count):residual+=k[i*4+j]*x[j]
            if (abs(residual)>1e-9 if x[i]>0 else residual < -1e-9):valid=False
        if valid and length<least:least=length;answer=x^
    return answer^

from std.collections import List
from std.math import isfinite
from mojo_game import RigidBody3D
from .box_oracle import OracleBox,box_axes,box_center
from .coupled_geometry_reference import ReferenceBox,ReferencePoint,face,direction,scalar_cross,scalar_dot,vertex_gap,reference_patch,reference_edge
from .response_reference import inverse_tensor,energy,inv_mass,point_speed,profile
from .friction_reference import relative,push,delta_velocity,cpu_basis,spectral_min
from .coupled_friction_reference import cpu_coupled_patch

def reference_operators(k: Array[Float64,16],count: Int) -> Array[Float64,256]:
    var output=Array[Float64,256](fill=0)
    for mask in range(1<<count):
        for col in range(count):
            var q=Array[Float64,4](fill=0);q[col]=-1;var result=reference_linear(k,q,mask)
            for row in range(count):output[mask*16+row*4+col]=result[row]
    return output^

def reference_cached(k: Array[Float64,16],q: Array[Float64,4],operators: Array[Float64,256],count: Int,tolerance: Float64=1e-9) raises -> Array[Float64,4]:
    var best=Array[Float64,4](fill=0);var minimum=Float64(1e300)
    for mask in range(1<<count):
        var x=Array[Float64,4](fill=0);var valid=True;var norm=Float64(0)
        for i in range(count):
            for j in range(count):x[i]-=operators[mask*16+i*4+j]*q[j]
            if x[i]<-1e-10:valid=False
            x[i]=max(0.0,x[i]);norm+=x[i]*x[i]
        for i in range(count):
            var residual=q[i]
            for j in range(count):residual+=k[i*4+j]*x[j]
            if (abs(residual)>tolerance if x[i]>0 else residual < -tolerance):valid=False
        if valid and norm<minimum:minimum=norm;best=x^
    if minimum==1e300:raise Error("CPU PSD block has no feasible impulse")
    return best^

@fieldwise_init
struct CpuPatch(Movable):
    var a: Int
    var b: Int
    var origin: Vec3
    var normal: Vec3
    var gap: Float64
    var points: List[ReferencePoint]

def reference_input(model: OracleBox) -> ReferenceBox:
    var axes=box_axes(model)
    return ReferenceBox(box_center(model),axes[0]*model.half_extents.x,axes[1]*model.half_extents.y,axes[2]*model.half_extents.z)

def cpu_geometry(models: List[OracleBox],conventions: List[Int32]) raises -> List[CpuPatch]:
    var output=List[CpuPatch]()
    for i in range(len(models)):
        for j in range(i+1,len(models)):
            if models[i].body_handle.slot==models[j].body_handle.slot or (models[i].body.properties.mass==0 and models[j].body.properties.mass==0):continue
            var a=reference_input(models[i]);var b=reference_input(models[j]);var hit=True;var greatest=Float64(-1e300);var selected=0;var n=Vec3(0,1,0)
            for code in range(15):
                var axis=face(a,code) if code<3 else face(b,code-3) if code<6 else direction(scalar_cross(a.edge((code-6)//3),b.edge((code-6)%3)))
                if scalar_dot(axis,axis)==0:continue
                var gap=vertex_gap(a,b,axis)
                if gap>0:hit=False;break
                var magnitude=Float64(1)
                for vertex in range(8):magnitude=max(magnitude,abs(scalar_dot(a.vertex(vertex,a.center),axis))+abs(scalar_dot(b.vertex(vertex,a.center),axis)))
                if code==0 or gap>greatest+(32*2.220446049250313e-16*magnitude if code>=6 else 0):greatest=gap;selected=code;n=axis if scalar_dot(b.center-a.center,axis)>=0 else axis*(-1)
            if not hit:continue
            var key=Int(models[i].shape.slot)*(128-Int(models[i].shape.slot)-1)//2+Int(models[j].shape.slot)-Int(models[i].shape.slot)-1
            if len(conventions)>key and conventions[key]>=0 and Int(conventions[key])!=selected:
                var code=Int(conventions[key])
                if code>=6 or selected>=6:raise Error("Independent resolved SAT feature disagrees")
                var candidate=face(a,code) if code<3 else face(b,code-3);var alternate=vertex_gap(a,b,candidate)
                var magnitude=Float64(1)
                for vertex in range(8):magnitude=max(magnitude,abs(scalar_dot(a.vertex(vertex,a.center),candidate))+abs(scalar_dot(b.vertex(vertex,a.center),candidate)))
                if abs(alternate-greatest)>64*2.220446049250313e-16*magnitude or abs(scalar_dot(candidate,n))<1-1024*2.220446049250313e-16:raise Error("Independent SAT does not verify a representation-scale face tie")
                selected=code;greatest=alternate;n=candidate if scalar_dot(b.center-a.center,candidate)>=0 else candidate*(-1)
            var points=reference_patch(a,b,selected,32*2.220446049250313e-16*max(1.0,max(models[i].half_extents.length(),models[j].half_extents.length()))) if selected<6 else List[ReferencePoint]()
            if selected>=6:points.append(reference_edge(a,b,selected))
            output.append(CpuPatch(i,j,a.center,n,greatest,points^))
    return output^

def selected_points(p: CpuPatch) -> List[Vec3]:
    # Independent reference polygon is cyclic from its constructive hull. Pick
    # maximum-area inscribed quadrilateral directly in 3D, without GPU UV hull.
    var candidates=List[Vec3]()
    for point in p.points:candidates.append(p.origin+(point.a+point.b)*.5)
    var result=List[Vec3]()
    if len(candidates)<=4:result=candidates.copy()
    else:
        var best=Float64(-1);var chosen=Array[Int,4](fill=0)
        for i in range(len(candidates)):
            for j in range(i+1,len(candidates)):
                for k in range(j+1,len(candidates)):
                    for l in range(k+1,len(candidates)):
                        var a=candidates[i];var b=candidates[j];var c=candidates[k];var d=candidates[l]
                        var area=abs(scalar_dot(scalar_cross(b-a,c-a)+scalar_cross(c-a,d-a),p.normal))
                        if area>best+1.5e-14*(1+abs(best)):best=area;chosen[0]=i;chosen[1]=j;chosen[2]=k;chosen[3]=l
        for i in range(4):result.append(candidates[chosen[i]])
    for i in range(len(result)):
        for j in range(i+1,len(result)):
            var a=result[i];var b=result[j]
            if b.x<a.x or (b.x==a.x and b.y<a.y) or (b.x==a.x and b.y==a.y and b.z<a.z):var saved=result[i];result[i]=result[j];result[j]=saved
    return result^

@fieldwise_init
struct CpuConstraint(Movable):
    var a: Int
    var b: Int
    var n: Vec3
    var points: List[Vec3]
    var gram: Array[Float64,16]
    var operators: Array[Float64,256]
    var normal_impulse: Array[Float64,4]
    var tangent_impulse: Array[Vec3,4]
    var targets: Array[Float64,4]

@fieldwise_init
struct CpuBoxResult(Movable):
    var models: List[OracleBox]
    var impulses: List[Float64]
    var normal_residual: Float64
    var tangent_residual: Float64
    var maximum_depth: Float64
    var maximum_shift: Float64
    var kinetic_before: Float64
    var kinetic_after: Float64
    var velocity_sweeps: Int
    var position_sweeps: Int

struct CpuCoupledBoxResponse(Movable):
    var last_error: Int32
    var velocity_budget: Int
    var conventions: List[Int32]
    var normal_history: List[Float64]
    var last_normal_residual: Float64
    var last_position_residual: Float64
    def __init__(out self,velocity_budget: Int=64):self.last_error=0;self.velocity_budget=velocity_budget;self.conventions=List[Int32]();self.normal_history=List[Float64]();self.last_normal_residual=0;self.last_position_residual=0
    def fail(mut self,code: Int32) raises:
        self.last_error=code;raise Error("CPU box reference rejected="+String(code))
    def solve(mut self,input: List[OracleBox],dt: Float64,e: Float64=0,mu: Float64=0,iterations: Int=32,position_iterations: Int=32) raises -> CpuBoxResult:
        self.last_error=0;self.normal_history.clear()
        if not isfinite(dt) or dt<1.0/240 or dt>1.0/30 or not isfinite(e) or e<0 or e>1 or not isfinite(mu) or mu<0 or mu>2 or iterations<1 or iterations>self.velocity_budget or position_iterations<1 or position_iterations>64:self.fail(111)
        var models=input.copy()
        for model in models:
            if not profile(model.body):self.fail(117)
        var initial=cpu_geometry(models,self.conventions);var pressure=List[Float64]()
        for index in range(len(initial)):
            if -initial[index].gap>.25:self.fail(115)
            pressure.append(0)
        if len(initial)>16:self.fail(110)
        var shift=Float64(0);var position_used=0;var position_converged=False
        for sweep in range(position_iterations):
            for i in range(len(initial)):
                ref p=initial[i];var a=models[p.a].body;var b=models[p.b].body
                var error=p.gap+scalar_dot((b.position-input[p.b].body.position)-(a.position-input[p.a].body.position),p.normal)+1e-5
                var next=max(0.0,pressure[i]-error/(inv_mass(a)+inv_mass(b)));var delta=p.normal*(next-pressure[i]);pressure[i]=next
                if a.properties.mass>0:a.position=a.position-delta*inv_mass(a)
                if b.properties.mass>0:b.position=b.position+delta*inv_mass(b)
                models[p.a].body=a;models[p.b].body=b
                shift=max(shift,max((a.position-input[p.a].body.position).length(),(b.position-input[p.b].body.position).length()))
                if shift>.25:self.fail(115)
            var residual=Float64(0)
            for i in range(len(initial)):
                ref p=initial[i];var error=p.gap+scalar_dot((models[p.b].body.position-input[p.b].body.position)-(models[p.a].body.position-input[p.a].body.position),p.normal)+1e-5
                residual=max(residual,abs(error) if pressure[i]>0 else max(0.0,-error))
            self.last_position_residual=residual;position_used=sweep+1;position_converged=residual<=1e-9
            if position_converged:break
        if not position_converged:self.fail(115)
        var fresh=cpu_geometry(models,self.conventions);var constraints=List[CpuConstraint]();var maximum_depth=Float64(0);var normal_tolerance=Float64(1e-9);var tangent_tolerance=Float64(1e-9)
        for index in range(len(fresh)):
            ref p=fresh[index];var found=False
            for i in range(len(initial)):
                if initial[i].a==p.a and initial[i].b==p.b:found=True
            if not found:self.fail(119)
            maximum_depth=max(maximum_depth,-p.gap)
            if p.gap < -1e-5-1e-9:self.fail(116)
            var points=selected_points(p);var a=models[p.a].body;var b=models[p.b].body;var gram=Array[Float64,16](fill=0);var targets=Array[Float64,4](fill=0)
            for i in range(len(points)):
                var incoming=point_speed(a,b,points[i],p.normal);targets[i]=-e*incoming if incoming<-.2 else 0;normal_tolerance=max(normal_tolerance,1e-9*(1+abs(incoming)))
                var v=relative(a,b,points[i]);tangent_tolerance=max(tangent_tolerance,1e-9*(1+(v-p.normal*scalar_dot(v,p.normal)).length()))
                for j in range(len(points)):
                    # Effective velocity response to unit impulse at point j,
                    # independently of the GPU explicit inverse-inertia Gram.
                    gram[i*4+j]=scalar_dot(delta_velocity(a,b,points[i],p.normal),p.normal) if i==j else 0
                    if i!=j:
                        var ca=a;var cb=b;push(ca,cb,points[j],p.normal);gram[i*4+j]=point_speed(ca,cb,points[i],p.normal)-point_speed(a,b,points[i],p.normal)
            var operators=reference_operators(gram,len(points))
            constraints.append(CpuConstraint(p.a,p.b,p.normal,points^,gram^,operators^,Array[Float64,4](fill=0),Array[Vec3,4](fill=Vec3(0,0,0)),targets^))
        var projected=models.copy();var touched=Array[Bool,64](fill=False)
        for index in range(len(constraints)):touched[constraints[index].a]=True;touched[constraints[index].b]=True
        var before=Float64(0)
        for index in range(len(models)):
            if touched[index]:before+=energy(models[index].body)
        var converged=len(constraints)==0;var used=0;var normal_residual=Float64(0);var tangent_residual=Float64(0)
        for sweep in range(iterations):
            if converged and mu==0:break
            for index in range(len(constraints)):
                ref c=constraints[index];var a=models[c.a].body;var b=models[c.b].body;var q=Array[Float64,4](fill=0)
                for i in range(len(c.points)):
                    q[i]=point_speed(a,b,c.points[i],c.n)-c.targets[i]
                    for j in range(len(c.points)):q[i]-=c.gram[i*4+j]*c.normal_impulse[j]
                var accelerated=False
                if mu>0:
                    var coupled=cpu_coupled_patch(a,b,c.n,c.points,c.gram,c.operators,c.targets,c.normal_impulse,c.tangent_impulse,normal_tolerance,mu)
                    if coupled.accepted:
                        a=coupled.a;b=coupled.b;c.normal_impulse=coupled.pressure.copy();c.tangent_impulse=coupled.tangent.copy();accelerated=True
                if not accelerated:
                    var next=Array[Float64,4](fill=0)
                    try:next=reference_cached(c.gram,q,c.operators,len(c.points),normal_tolerance)
                    except:self.fail(113)
                    for i in range(len(c.points)):push(a,b,c.points[i],c.n*(next[i]-c.normal_impulse[i]));c.normal_impulse[i]=next[i]
                    if mu>0:
                        var basis=cpu_basis(c.n);var t=basis[0];var u=basis[1]
                        for i in range(len(c.points)):
                            var p=c.points[i];var response_t=delta_velocity(a,b,p,t);var response_u=delta_velocity(a,b,p,u);var k=Vec3(scalar_dot(response_t,t),scalar_dot(response_t,u),scalar_dot(response_u,u));var old=c.tangent_impulse[i]
                            var free=relative(a,b,p)-delta_velocity(a,b,p,old);var trial=spectral_min(k,Vec3(scalar_dot(free,t),scalar_dot(free,u),0),mu*c.normal_impulse[i]);var world=t*trial.x+u*trial.y;push(a,b,p,world-old);c.tangent_impulse[i]=world
                if not profile(a) or not profile(b):self.fail(117)
                models[c.a].body=a;models[c.b].body=b
            normal_residual=0;tangent_residual=0
            for index in range(len(constraints)):
                ref c=constraints[index];var a=models[c.a].body;var b=models[c.b].body;var basis=cpu_basis(c.n);var t=basis[0];var u=basis[1]
                for i in range(len(c.points)):
                    var error=point_speed(a,b,c.points[i],c.n)-c.targets[i];normal_residual=max(normal_residual,abs(error) if c.normal_impulse[i]>0 else max(0.0,-error))
                    if mu>0:
                        var p=c.points[i];var response_t=delta_velocity(a,b,p,t);var response_u=delta_velocity(a,b,p,u);var k=Vec3(scalar_dot(response_t,t),scalar_dot(response_t,u),scalar_dot(response_u,u));var old=c.tangent_impulse[i];var free=relative(a,b,p)-delta_velocity(a,b,p,old);var optimum=spectral_min(k,Vec3(scalar_dot(free,t),scalar_dot(free,u),0),mu*c.normal_impulse[i]);var d=old-t*optimum.x-u*optimum.y
                        var response=delta_velocity(a,b,p,d);tangent_residual=max(tangent_residual,sqrt(scalar_dot(response,t)*scalar_dot(response,t)+scalar_dot(response,u)*scalar_dot(response,u)))
            self.normal_history.append(normal_residual);self.last_normal_residual=normal_residual;used=sweep+1;converged=normal_residual<=normal_tolerance and tangent_residual<=tangent_tolerance
        if not converged:self.fail(114)
        var after=Float64(0)
        for index in range(len(models)):
            if touched[index]:after+=energy(models[index].body)
        if after>before+1e-9*(1+before):self.fail(118)
        var output=List[Float64]()
        for index in range(len(constraints)):
            ref c=constraints[index]
            for i in range(len(c.points)):output.append(c.normal_impulse[i])
        # Unreduced current vertices remain validity constraints after reduction.
        for index in range(len(fresh)):
            ref p=fresh[index]
            for vertex in p.points:
                var midpoint=p.origin+(vertex.a+vertex.b)*.5
                var incoming=point_speed(projected[p.a].body,projected[p.b].body,midpoint,p.normal);var target=-e*incoming if incoming<-.2 else 0.0
                if point_speed(models[p.a].body,models[p.b].body,midpoint,p.normal)<target-normal_tolerance:self.fail(116)
        return CpuBoxResult(models^,output^,normal_residual,tangent_residual,maximum_depth,shift,before,after,used,position_used)
