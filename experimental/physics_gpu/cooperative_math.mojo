"""Block-uniform exact point cooperation; serial controller arithmetic retained."""
from max.gpu import thread_idx
from max.gpu.sync import barrier
from std.memory import stack_allocation,AddressSpace,Pointer
from std.collections import Array
from std.math import isfinite
from mojo_game import Vec3
from .friction_kernels import disk_min
from .box_response_math import cached_normal_block
from .coupled_friction_math import CoupledEvaluation

comptime SharedFloat=Pointer[Float64,MutUntrackedOrigin,address_space=AddressSpace.SHARED]
comptime SharedInt=Pointer[Int32,MutUntrackedOrigin,address_space=AddressSpace.SHARED]
@fieldwise_init
struct PointEvaluation(Movable):
    var values: Array[Float64,18]
    var stage: Int32

def point_worker(nt: Array[Float64,32],tt: Array[Float64,64],pressure: Array[Float64,4],qt: Array[Float64,8],x: Array[Float64,8],dp: Array[Float64,32],count: Int,mu: Float64,jacobian: Bool,i: Int) -> PointEvaluation:
    var result=PointEvaluation(Array[Float64,18](fill=0),0)
    var ix=2*i;var iy=ix+1;var mass=Vec3(tt[ix*8+ix],tt[ix*8+iy],tt[iy*8+iy]);var velocity=Vec3(qt[ix],qt[iy],0)
    for k in range(count):velocity.x+=nt[k*8+ix]*pressure[k];velocity.y+=nt[k*8+iy]*pressure[k]
    for k in range(count*2):velocity.x+=tt[ix*8+k]*x[k];velocity.y+=tt[iy*8+k]*x[k]
    var free=Vec3(velocity.x-mass.x*x[ix]-mass.y*x[iy],velocity.y-mass.y*x[ix]-mass.z*x[iy],0);var radius=mu*pressure[i];var best=disk_min(mass,free,radius)
    if not isfinite(best.x) or not isfinite(best.y) or not isfinite(best.z):return result^
    result.values[0]=x[ix]-best.x;result.values[1]=x[iy]-best.y;result.stage=1
    if not jacobian:result.stage=2;return result^
    # Implicit disk derivative; using j/r avoids squaring tiny radii.
    var du00=Float64(0);var du01=Float64(0);var du11=Float64(0);var dr0=Float64(0);var dr1=Float64(0)
    if radius>0:
        var a=mass.x+best.z;var b=mass.y;var d=mass.z+best.z;var determinant=a*d-b*b
        if not isfinite(determinant) or determinant<=0:return result^
        var aa=d/determinant;var ab=-b/determinant;var dd=a/determinant
        du00=-aa;du01=-ab;du11=-dd
        if best.z>0:
            var unit=Vec3(best.x/radius,best.y/radius,0);var ad=Vec3(aa*unit.x+ab*unit.y,ab*unit.x+dd*unit.y,0);var denominator=unit.dot(ad)
            if not isfinite(denominator) or denominator<=0:return result^
            du00+=ad.x*ad.x/denominator;du01+=ad.x*ad.y/denominator;du11+=ad.y*ad.y/denominator;dr0=ad.x/denominator;dr1=ad.y/denominator
    for j in range(count*2):
        var ux=tt[ix*8+j];var uy=tt[iy*8+j]
        for k in range(count):ux+=nt[k*8+ix]*dp[k*8+j];uy+=nt[k*8+iy]*dp[k*8+j]
        if j==ix:ux-=mass.x;uy-=mass.y
        if j==iy:ux-=mass.y;uy-=mass.z
        result.values[2+j]=(1.0 if ix==j else 0.0)-du00*ux-du01*uy-dr0*mu*dp[i*8+j]
        result.values[10+j]=(1.0 if iy==j else 0.0)-du01*ux-du11*uy-dr1*mu*dp[i*8+j]
    result.stage=2;return result^


def point_phase(shared: SharedFloat,flags: SharedInt,lane: Int):
    var count=Int(flags[unsafe_offset=16]);var jacobian=flags[unsafe_offset=17]!=0
    if flags[unsafe_offset=22]==0 or lane>=count:return
    var nt=Array[Float64,32](fill=0);var tt=Array[Float64,64](fill=0);var pressure=Array[Float64,4](fill=0);var qt=Array[Float64,8](fill=0);var x=Array[Float64,8](fill=0);var dp=Array[Float64,32](fill=0)
    for i in range(32):nt[i]=shared[unsafe_offset=17+i];dp[i]=shared[unsafe_offset=391+i]
    for i in range(64):tt[i]=shared[unsafe_offset=49+i]
    for i in range(4):pressure[i]=shared[unsafe_offset=423+i]
    for i in range(8):qt[i]=shared[unsafe_offset=373+i];x[i]=shared[unsafe_offset=381+i]
    var point=point_worker(nt,tt,pressure,qt,x,dp,count,shared[unsafe_offset=389],jacobian,lane)
    flags[unsafe_offset=18+lane]=point.stage
    shared[unsafe_offset=427+lane*2]=point.values[0];shared[unsafe_offset=428+lane*2]=point.values[1]
    for j in range(8):shared[unsafe_offset=435+(lane*2)*8+j]=point.values[2+j];shared[unsafe_offset=435+(lane*2+1)*8+j]=point.values[10+j]

def evaluate_cooperative(nn: Array[Float64,16],nt: Array[Float64,32],tt: Array[Float64,64],operators: Array[Float64,256],valid_masks: Array[Bool,16],qn: Array[Float64,4],qt: Array[Float64,8],x: Array[Float64,8],count: Int,mu: Float64,tolerance: Float64,jacobian: Bool,shared: SharedFloat,flags: SharedInt,debug: Pointer[Int64,MutAnyOrigin],parallel: Bool) -> CoupledEvaluation:
    var lane=Int(thread_idx.x)
    var result=CoupledEvaluation(Array[Float64,4](fill=0),Array[Float64,8](fill=0),Array[Float64,64](fill=0),False)
    if lane==0:
        shared[unsafe_offset=0]=-987654321.25
        for i in range(499,506):shared[unsafe_offset=i]=-987654321.25
        for i in range(16):shared[unsafe_offset=1+i]=nn[i];flags[unsafe_offset=i]=Int32(1 if valid_masks[i] else 0)
        for i in range(32):shared[unsafe_offset=17+i]=nt[i]
        for i in range(64):shared[unsafe_offset=49+i]=tt[i]
        for i in range(256):shared[unsafe_offset=113+i]=operators[i]
        for i in range(4):shared[unsafe_offset=369+i]=qn[i]
        for i in range(8):shared[unsafe_offset=373+i]=qt[i];shared[unsafe_offset=381+i]=x[i]
        shared[unsafe_offset=389]=mu;shared[unsafe_offset=390]=tolerance
        flags[unsafe_offset=16]=Int32(count);flags[unsafe_offset=17]=Int32(1 if jacobian else 0);flags[unsafe_offset=22]=0;flags[unsafe_offset=23]=-1
        for i in range(391,499):shared[unsafe_offset=i]=0
        for i in range(4):flags[unsafe_offset=18+i]=-1
    barrier()
    if lane==0:
        var q=qn.copy()
        for i in range(count):
            for j in range(count*2):q[i]+=nt[i*8+j]*x[j]
        var pressure=cached_normal_block(nn,q,operators,valid_masks,count,tolerance)
        if pressure.valid:
            var mask=0
            for i in range(4):shared[unsafe_offset=423+i]=pressure.impulse[i]
            for i in range(count):
                if pressure.impulse[i]>0:mask|=1<<i
            flags[unsafe_offset=22]=1
            if jacobian:
                if not valid_masks[mask]:flags[unsafe_offset=22]=0
                else:
                    for i in range(count):
                        for j in range(count*2):
                            var value=Float64(0)
                            for k in range(count):value-=operators[mask*16+i*4+k]*nt[k*8+j]
                            shared[unsafe_offset=391+i*8+j]=value
    barrier()
    if parallel:point_phase(shared,flags,lane)
    elif lane==0:
        for i in range(count):point_phase(shared,flags,i)
    barrier()
    if lane==0:
        result.valid=flags[unsafe_offset=22]!=0
        if result.valid:
            for i in range(count):
                if flags[unsafe_offset=18+i]!=2:flags[unsafe_offset=23]=Int32(i);result.valid=False;break
        var first_bad=Int(flags[unsafe_offset=23])
        if first_bad>=0:
            for i in range(first_bad+1,count):
                shared[unsafe_offset=427+i*2]=0;shared[unsafe_offset=428+i*2]=0
                for j in range(8):shared[unsafe_offset=435+(2*i)*8+j]=0;shared[unsafe_offset=435+(2*i+1)*8+j]=0
        for i in range(4):result.pressure[i]=shared[unsafe_offset=423+i]
        for i in range(8):result.residual[i]=shared[unsafe_offset=427+i]
        for i in range(64):result.jacobian[i]=shared[unsafe_offset=435+i]
        var intact=shared[unsafe_offset=0]==-987654321.25 and flags[unsafe_offset=29]==-98765
        for i in range(499,506):intact=intact and shared[unsafe_offset=i]==-987654321.25
        for i in range(count,4):intact=intact and flags[unsafe_offset=18+i]==-1
        debug[unsafe_offset=1]+=1;debug[unsafe_offset=2]+=Int64(count if flags[unsafe_offset=22] else 0)
        debug[unsafe_offset=3]+=Int64(1 if jacobian else 0);debug[unsafe_offset=4]+=Int64(1 if first_bad>=0 else 0)
        debug[unsafe_offset=6+count]+=1
        if not intact:flags[unsafe_offset=28]=0;debug[unsafe_offset=5]+=1;result.valid=False
    barrier()
    return result^
