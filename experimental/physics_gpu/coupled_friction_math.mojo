"""Cold within-patch coupled Coulomb roots; no state publication or warm cache."""
from std.collections import Array
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .box_response_math import cached_normal_block
from .friction_kernels import disk_min
from .box_box_kernels import EPS

@fieldwise_init
struct CoupledEvaluation(Movable):
    var pressure: Array[Float64,4]
    var residual: Array[Float64,8]
    var jacobian: Array[Float64,64]
    var valid: Bool

@fieldwise_init
struct CoupledLinear(Movable):
    var value: Array[Float64,8]
    var rank: Int
    var valid: Bool

def linear8(h: Array[Float64,64],rhs: Array[Float64,8],count: Int) -> CoupledLinear:
    var rows=Array[Float64,72](fill=0);var order=Array[Int,8](fill=0);var rank=0;var scale=Float64(0)
    for i in range(count):
        order[i]=i
        for j in range(count):rows[i*9+j]=h[i*8+j];scale=max(scale,abs(h[i*8+j]))
        rows[i*9+8]=rhs[i]
    var output=CoupledLinear(Array[Float64,8](fill=0),0,True)
    if scale==0:return output^
    # Choose a pivot from the entire remaining block. Fixed column order can
    # divide by a weak geometric column and amplify null-space roundoff into
    # a false rank. The original256eps cutoff and eight-step bound stay intact.
    for step in range(count):
        var best=Float64(0);var row=step;var col=step
        for i in range(step,count):
            for j in range(step,count):
                if abs(rows[i*9+j])>best:best=abs(rows[i*9+j]);row=i;col=j
        if best<=256*EPS*scale:break
        for j in range(9):var saved=rows[step*9+j];rows[step*9+j]=rows[row*9+j];rows[row*9+j]=saved
        for i in range(count):var saved=rows[i*9+step];rows[i*9+step]=rows[i*9+col];rows[i*9+col]=saved
        var saved_order=order[step];order[step]=order[col];order[col]=saved_order
        var pivot=rows[step*9+step]
        for j in range(9):rows[step*9+j]/=pivot
        for i in range(count):
            if i==step:continue
            var factor=rows[i*9+step]
            for j in range(9):rows[i*9+j]-=factor*rows[step*9+j]
        rank+=1
    var solution=Array[Float64,8](fill=0)
    for i in range(rank):solution[i]=rows[i*9+8]
    var nulls=Array[Float64,64](fill=0);var used=0
    for col in range(rank,count):
        var v=Array[Float64,8](fill=0);v[col]=1
        for row in range(rank):v[row]=-rows[row*9+col]
        for basis in range(used):
            var dot=Float64(0)
            for j in range(count):dot+=v[j]*nulls[basis*8+j]
            for j in range(count):v[j]-=dot*nulls[basis*8+j]
        var length=Float64(0)
        for j in range(count):length+=v[j]*v[j]
        length=sqrt(length)
        if not isfinite(length) or length==0:output.valid=False;return output^
        for j in range(count):nulls[used*8+j]=v[j]/length
        used+=1
    for basis in range(used):
        var dot=Float64(0)
        for j in range(count):dot+=solution[j]*nulls[basis*8+j]
        for j in range(count):solution[j]-=dot*nulls[basis*8+j]
    for j in range(count):
        output.value[order[j]]=solution[j]
        if not isfinite(solution[j]):output.valid=False
    output.rank=rank;return output^

def evaluate_coupled(nn: Array[Float64,16],nt: Array[Float64,32],tt: Array[Float64,64],operators: Array[Float64,256],valid: Array[Bool,16],qn: Array[Float64,4],qt: Array[Float64,8],x: Array[Float64,8],count: Int,mu: Float64,normal_tolerance: Float64,jacobian: Bool) -> CoupledEvaluation:
    var result=CoupledEvaluation(Array[Float64,4](fill=0),Array[Float64,8](fill=0),Array[Float64,64](fill=0),False);var q=qn.copy()
    for i in range(count):
        for j in range(count*2):q[i]+=nt[i*8+j]*x[j]
    var pressure=cached_normal_block(nn,q,operators,valid,count,normal_tolerance)
    if not pressure.valid:return result^
    result.pressure=pressure.impulse.copy();result.valid=True
    var dp=Array[Float64,32](fill=0);var mask=0
    for i in range(count):
        if result.pressure[i]>0:mask|=1<<i
    if jacobian:
        if not valid[mask]:result.valid=False;return result^
        for i in range(count):
            for j in range(count*2):
                for k in range(count):dp[i*8+j]-=operators[mask*16+i*4+k]*nt[k*8+j]
    for i in range(count):
        var ix=2*i;var iy=ix+1;var mass=Vec3(tt[ix*8+ix],tt[ix*8+iy],tt[iy*8+iy]);var velocity=Vec3(qt[ix],qt[iy],0)
        for k in range(count):velocity.x+=nt[k*8+ix]*result.pressure[k];velocity.y+=nt[k*8+iy]*result.pressure[k]
        for k in range(count*2):velocity.x+=tt[ix*8+k]*x[k];velocity.y+=tt[iy*8+k]*x[k]
        var free=Vec3(velocity.x-mass.x*x[ix]-mass.y*x[iy],velocity.y-mass.y*x[ix]-mass.z*x[iy],0);var radius=mu*result.pressure[i];var best=disk_min(mass,free,radius)
        if not isfinite(best.x) or not isfinite(best.y) or not isfinite(best.z):result.valid=False;return result^
        result.residual[ix]=x[ix]-best.x;result.residual[iy]=x[iy]-best.y
        if not jacobian:continue
        # Implicit disk derivative; using j/r avoids squaring tiny radii.
        var du00=Float64(0);var du01=Float64(0);var du11=Float64(0);var dr0=Float64(0);var dr1=Float64(0)
        if radius>0:
            var a=mass.x+best.z;var b=mass.y;var d=mass.z+best.z;var determinant=a*d-b*b
            if not isfinite(determinant) or determinant<=0:result.valid=False;return result^
            var aa=d/determinant;var ab=-b/determinant;var dd=a/determinant
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

def coupled_norm(f: Array[Float64,8],count: Int) -> Float64:
    var value=Float64(0)
    for i in range(count):value=max(value,abs(f[i]))
    return value
