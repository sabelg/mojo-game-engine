"""Independent scalar/unit-impulse/spectral reference for the opt-in policy.
No GPU pressure, derivative, matrix or Newton helper is called. Complete pivoting
provides a distinct least-norm correction; closed-form/SVD model checks supplement
this replay, so CPU/GPU agreement is not the only mathematical evidence.
"""
from std.collections import Array,List
from std.math import sqrt,isfinite
from mojo_game import Vec3,RigidBody3D
from .box_response_reference import reference_cached
from .friction_reference import spectral_min,cpu_basis,relative,push
from .response_reference import profile,point_speed

@fieldwise_init
struct CpuCoupledEvaluation(Movable):
    var pressure: Array[Float64,4]
    var residual: Array[Float64,8]
    var jacobian: Array[Float64,64]
    var valid: Bool

@fieldwise_init
struct CpuCoupledLinear(Movable):
    var value: Array[Float64,8]
    var rank: Int
    var valid: Bool

@fieldwise_init
struct CpuCoupledPatch(Movable):
    var a: RigidBody3D
    var b: RigidBody3D
    var pressure: Array[Float64,4]
    var tangent: Array[Vec3,4]
    var accepted: Bool

comptime EPS=Float64(2.220446049250313e-16)

def cpu_linear8(h: Array[Float64,64],rhs: Array[Float64,8],count: Int) -> CpuCoupledLinear:
    var rows=Array[Float64,72](fill=0);var order=Array[Int,8](fill=0);var rank=0;var scale=Float64(0)
    for i in range(count):
        order[i]=i
        for j in range(count):rows[i*9+j]=h[i*8+j];scale=max(scale,abs(h[i*8+j]))
        rows[i*9+8]=rhs[i]
    var result=CpuCoupledLinear(Array[Float64,8](fill=0),0,True)
    for step in range(count):
        var best=Float64(0);var pr=step;var pc=step
        for i in range(step,count):
            for j in range(step,count):
                if abs(rows[i*9+j])>best:best=abs(rows[i*9+j]);pr=i;pc=j
        if best<=256*EPS*scale:break
        for j in range(9):var old=rows[step*9+j];rows[step*9+j]=rows[pr*9+j];rows[pr*9+j]=old
        for i in range(count):var old=rows[i*9+step];rows[i*9+step]=rows[i*9+pc];rows[i*9+pc]=old
        var saved=order[step];order[step]=order[pc];order[pc]=saved;var pivot=rows[step*9+step]
        for j in range(9):rows[step*9+j]/=pivot
        for i in range(count):
            if i==step:continue
            var factor=rows[i*9+step]
            for j in range(9):rows[i*9+j]-=factor*rows[step*9+j]
        rank+=1
    for i in range(rank):result.value[order[i]]=rows[i*9+8]
    var basis=Array[Float64,64](fill=0);var used=0
    for col in range(rank,count):
        var v=Array[Float64,8](fill=0);v[order[col]]=1
        for i in range(rank):v[order[i]]=-rows[i*9+col]
        for k in range(used):
            var dot=Float64(0)
            for i in range(count):dot+=v[i]*basis[k*8+i]
            for i in range(count):v[i]-=dot*basis[k*8+i]
        var length=Float64(0)
        for i in range(count):length+=v[i]*v[i]
        length=sqrt(length)
        if not isfinite(length) or length==0:result.valid=False;return result^
        for i in range(count):basis[used*8+i]=v[i]/length
        used+=1
    for k in range(used):
        var dot=Float64(0)
        for i in range(count):dot+=result.value[i]*basis[k*8+i]
        for i in range(count):result.value[i]-=dot*basis[k*8+i]
    for i in range(count):
        if not isfinite(result.value[i]):result.valid=False
    result.rank=rank;return result^

def cpu_evaluate_coupled(nn: Array[Float64,16],nt: Array[Float64,32],tt: Array[Float64,64],operators: Array[Float64,256],valid: Array[Bool,16],qn: Array[Float64,4],qt: Array[Float64,8],x: Array[Float64,8],count: Int,mu: Float64,normal_tolerance: Float64,jacobian: Bool) raises -> CpuCoupledEvaluation:
    var result=CpuCoupledEvaluation(Array[Float64,4](fill=0),Array[Float64,8](fill=0),Array[Float64,64](fill=0),False);var q=qn.copy()
    for i in range(count):
        for j in range(count*2):q[i]+=nt[i*8+j]*x[j]
    var pressure=Array[Float64,4](fill=0)
    try:pressure=reference_cached(nn,q,operators,count,normal_tolerance)
    except:return result^
    result.pressure=pressure.copy();result.valid=True
    var dp=Array[Float64,32](fill=0);var mask=0
    for i in range(count):
        if result.pressure[i]>0:mask|=1<<i
    if jacobian:
        for i in range(count):
            for j in range(count*2):
                for k in range(count):dp[i*8+j]-=operators[mask*16+i*4+k]*nt[k*8+j]
    for i in range(count):
        var ix=2*i;var iy=ix+1;var mass=Vec3(tt[ix*8+ix],tt[ix*8+iy],tt[iy*8+iy]);var velocity=Vec3(qt[ix],qt[iy],0)
        for k in range(count):velocity.x+=nt[k*8+ix]*result.pressure[k];velocity.y+=nt[k*8+iy]*result.pressure[k]
        for k in range(count*2):velocity.x+=tt[ix*8+k]*x[k];velocity.y+=tt[iy*8+k]*x[k]
        var free=Vec3(velocity.x-mass.x*x[ix]-mass.y*x[iy],velocity.y-mass.y*x[ix]-mass.z*x[iy],0);var radius=mu*result.pressure[i];var best=spectral_min(mass,free,radius)
        if not isfinite(best.x) or not isfinite(best.y) or not isfinite(best.z):result.valid=False;return result^
        result.residual[ix]=x[ix]-best.x;result.residual[iy]=x[iy]-best.y
        if not jacobian:continue
        # Implicit disk derivative; using j/r avoids squaring tiny radii.
        var du00=Float64(0);var du01=Float64(0);var du11=Float64(0);var dr0=Float64(0);var dr1=Float64(0)
        if radius>0:
            var large=(mass.x+mass.z+sqrt((mass.x-mass.z)**2+4*mass.y*mass.y))*.5;var small=(mass.x*mass.z-mass.y*mass.y)/large
            var ex=Float64(1);var ey=Float64(0)
            if mass.y!=0:ex=mass.y;ey=large-mass.x;var length=sqrt(ex*ex+ey*ey);ex/=length;ey/=length
            elif mass.z>mass.x:ex=0;ey=1
            var al=1/(large+best.z);var az=1/(small+best.z);var aa=ex*ex*al+ey*ey*az;var ab=ex*ey*(al-az);var dd=ey*ey*al+ex*ex*az
            du00=-aa;du01=-ab;du11=-dd
            if best.z>0:
                var unit=Vec3(best.x/radius,best.y/radius,0);var ad=Vec3(aa*unit.x+ab*unit.y,ab*unit.x+dd*unit.y,0);var denominator=unit.dot(ad)
                if not isfinite(denominator) or denominator<=0:result.valid=False;return result^
                du00+=ad.x*ad.x/denominator;du01+=ad.x*ad.y/denominator;du11+=ad.y*ad.y/denominator;dr0=ad.x/denominator;dr1=ad.y/denominator
        for j in range(count*2):
            var ux=tt[ix*8+j];var uy=tt[iy*8+j]
            for k in range(count):ux+=nt[k*8+ix]*dp[k*8+j];uy+=nt[k*8+iy]*dp[k*8+j]
            if j==ix:ux-=mass.x;uy-=mass.y
            if j==iy:ux-=mass.y;uy-=mass.z
            result.jacobian[ix*8+j]=(1.0 if ix==j else 0.0)-du00*ux-du01*uy-dr0*mu*dp[i*8+j]
            result.jacobian[iy*8+j]=(1.0 if iy==j else 0.0)-du01*ux-du11*uy-dr1*mu*dp[i*8+j]
    return result^

def cpu_norm(f: Array[Float64,8],count: Int) -> Float64:
    var value=Float64(0)
    for i in range(count):value=max(value,abs(f[i]))
    return value

def cpu_coupled_patch(a: RigidBody3D,b: RigidBody3D,n: Vec3,points: List[Vec3],nn: Array[Float64,16],operators: Array[Float64,256],targets: Array[Float64,4],old_n: Array[Float64,4],old_t: Array[Vec3,4],normal_tolerance: Float64,mu: Float64) raises -> CpuCoupledPatch:
    var count=len(points);var basis=cpu_basis(n);var t=basis[0];var u=basis[1];var valid=Array[Bool,16](fill=True)
    var result=CpuCoupledPatch(a,b,old_n.copy(),old_t.copy(),False);var nt=Array[Float64,32](fill=0);var tt=Array[Float64,64](fill=0);var qn=Array[Float64,4](fill=0);var qt=Array[Float64,8](fill=0);var x=Array[Float64,8](fill=0)
    for i in range(count):
        var v=relative(a,b,points[i]);qn[i]=point_speed(a,b,points[i],n)-targets[i];qt[2*i]=v.dot(t);qt[2*i+1]=v.dot(u);x[2*i]=old_t[i].dot(t);x[2*i+1]=old_t[i].dot(u)
        for j in range(count):
            for axis in range(2):
                var direction=t if axis==0 else u;var aa=a;var bb=b;push(aa,bb,points[j],direction);var response=relative(aa,bb,points[i])-v
                nt[i*8+2*j+axis]=response.dot(n);tt[2*i*8+2*j+axis]=response.dot(t);tt[(2*i+1)*8+2*j+axis]=response.dot(u)
    for i in range(count):
        for j in range(count):qn[i]-=nn[i*4+j]*old_n[j]
        for j in range(2*count):qn[i]-=nt[i*8+j]*x[j]
    for i in range(2*count):
        for j in range(count):qt[i]-=nt[j*8+i]*old_n[j]
        for j in range(2*count):qt[i]-=tt[i*8+j]*x[j]
    for _ in range(8):
        var f=cpu_evaluate_coupled(nn,nt,tt,operators,valid,qn,qt,x,count,mu,normal_tolerance,True)
        if not f.valid:break
        var error=cpu_norm(f.residual,count*2);var scale=Float64(1)
        for i in range(count*2):scale=max(scale,abs(x[i]))
        if error<=64*EPS*scale:break
        var rhs=Array[Float64,8](fill=0)
        for i in range(count*2):rhs[i]=-f.residual[i]
        var delta=cpu_linear8(f.jacobian,rhs,count*2)
        if not delta.valid:break
        var accepted=False;var factor=Float64(1)
        for _ in range(16):
            var candidate=x.copy()
            for i in range(count*2):candidate[i]+=factor*delta.value[i]
            var trial=cpu_evaluate_coupled(nn,nt,tt,operators,valid,qn,qt,candidate,count,mu,normal_tolerance,False)
            if trial.valid and cpu_norm(trial.residual,count*2)<error:x=candidate^;accepted=True;break
            factor*=.5
        if not accepted:break
    var final=cpu_evaluate_coupled(nn,nt,tt,operators,valid,qn,qt,x,count,mu,normal_tolerance,False)
    if not final.valid:return result^
    for i in range(count):
        var radius=mu*final.pressure[i];var length=sqrt(x[2*i]**2+x[2*i+1]**2)
        if not isfinite(length) or length>radius+1e-12*(1+radius):return result^
    for i in range(count):
        push(result.a,result.b,points[i],n*(final.pressure[i]-old_n[i]));var tangent=t*x[2*i]+u*x[2*i+1];push(result.a,result.b,points[i],tangent-old_t[i]);result.pressure[i]=final.pressure[i];result.tangent[i]=tangent
    if not profile(result.a) or not profile(result.b):return result^
    result.accepted=True;return result^
