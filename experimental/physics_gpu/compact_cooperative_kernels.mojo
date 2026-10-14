"""Opt-in original tangent basis/local metric reuse atop resolve-local NT/TT."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .core import BodyState,finite
from .kernels import load,store,CAPACITY
from .response_kernels import inv_mass,inv_inertia,kinetic,body_profile,normal,point,normal_speed,apply_normal
from .friction_kernels import tangent_axes,point_velocity,tangent_metric,disk_min,apply_tangent
from .box_response_math import cached_normal_block
from .coupled_friction_math import linear8,coupled_norm,CoupledEvaluation
from .box_box_kernels import EPS
from .box_response_kernels import BR_BLOCK,BR_CONE,BR_PROFILE,BR_VELOCITY,BR_ENERGY

from .coupled_box_kernels import cross_metric

from max.gpu import thread_idx
from max.gpu.sync import barrier
from std.memory import stack_allocation,AddressSpace
from .compact_cooperative_math import evaluate_cooperative,SharedFloat,SharedInt

def finish_cooperative(mut a: BodyState,mut b: BodyState,geometry: Pointer[Float64,MutAnyOrigin],start: Int,count: Int,nn: Array[Float64,16],operators: Array[Float64,256],valid: Array[Bool,16],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],normal_tolerance: Float64,mu: Float64,c: Float64,s: Float64,work: Pointer[Int64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],patch: Int,final: CoupledEvaluation,x: Array[Float64,8]) -> Bool:
    var n=normal(geometry,start);var basis=cached_patch_basis(metrics,patch);var t=basis[0];var u=basis[1]
    if not final.valid:return False
    for i in range(count):
        var radius=mu*final.pressure[i];var length=sqrt(x[2*i]*x[2*i]+x[2*i+1]*x[2*i+1])
        if not isfinite(length) or length>radius+1e-12*(1+radius):return False
    var aa=a;var bb=b
    for i in range(count):
        var p=point(geometry,start+i);apply_normal(aa,bb,p,n,final.pressure[i]-impulses[unsafe_offset=1+start+i]);apply_tangent(aa,bb,p,t*(x[2*i]-tangent[unsafe_offset=1+(start+i)*2])+u*(x[2*i+1]-tangent[unsafe_offset=2+(start+i)*2]))
    if not body_profile(aa) or not body_profile(bb):work[unsafe_offset=9]+=1;return False
    a=aa;b=bb
    for i in range(count):impulses[unsafe_offset=1+start+i]=final.pressure[i];tangent[unsafe_offset=1+(start+i)*2]=x[2*i];tangent[unsafe_offset=2+(start+i)*2]=x[2*i+1]
    work[unsafe_offset=1]+=1;return True

def attempt_cooperative(mut a: BodyState,mut b: BodyState,geometry: Pointer[Float64,MutAnyOrigin],start: Int,count: Int,nn: Array[Float64,16],operators: Array[Float64,256],valid: Array[Bool,16],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],normal_tolerance: Float64,mu: Float64,c: Float64,s: Float64,work: Pointer[Int64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],patch: Int,shared: SharedFloat,flags: SharedInt,debug: Pointer[Int64,MutAnyOrigin],parallel: Bool) -> Bool:
    var lane=Int(thread_idx.x)
    var nt=Array[Float64,32](fill=0);var tt=Array[Float64,64](fill=0);var qn=Array[Float64,4](fill=0);var qt=Array[Float64,8](fill=0);var x=Array[Float64,8](fill=0)
    if lane==0:
        work[unsafe_offset=0]+=1
        var n=normal(geometry,start);var basis=cached_patch_basis(metrics,patch);var t=basis[0];var u=basis[1]
        for i in range(count):
            var p=point(geometry,start+i);var velocity=point_velocity(a,b,p);qn[i]=normal_speed(a,b,p,n)-targets[unsafe_offset=1+start+i];qt[2*i]=velocity.dot(t);qt[2*i+1]=velocity.dot(u)
            x[2*i]=tangent[unsafe_offset=1+(start+i)*2];x[2*i+1]=tangent[unsafe_offset=2+(start+i)*2]
            for j in range(count):
                var base=1+patch*96
                nt[i*8+2*j]=metrics[unsafe_offset=base+i*8+2*j];nt[i*8+2*j+1]=metrics[unsafe_offset=base+i*8+2*j+1]
                tt[(2*i)*8+2*j]=metrics[unsafe_offset=base+32+(2*i)*8+2*j];tt[(2*i)*8+2*j+1]=metrics[unsafe_offset=base+32+(2*i)*8+2*j+1]
                tt[(2*i+1)*8+2*j]=metrics[unsafe_offset=base+32+(2*i+1)*8+2*j];tt[(2*i+1)*8+2*j+1]=metrics[unsafe_offset=base+32+(2*i+1)*8+2*j+1]
        for i in range(count):
            for j in range(count):qn[i]-=nn[i*4+j]*impulses[unsafe_offset=1+start+j]
            for j in range(count*2):qn[i]-=nt[i*8+j]*x[j]
        for i in range(count*2):
            for j in range(count):qt[i]-=nt[j*8+i]*impulses[unsafe_offset=1+start+j]
            for j in range(count*2):qt[i]-=tt[i*8+j]*x[j]
    var error=Float64(0);var direction_value=Array[Float64,8](fill=0)
    for _ in range(8):
        var evaluation=evaluate_cooperative(nn,nt,tt,operators,valid,qn,qt,x,count,mu,normal_tolerance,True,shared,flags,debug,parallel)
        if lane==0:
            work[unsafe_offset=4]+=1;flags[unsafe_offset=25]=0
            if evaluation.valid:
                error=coupled_norm(evaluation.residual,count*2);var scale=Float64(1)
                for i in range(count*2):scale=max(scale,abs(x[i]))
                if not error<=64*EPS*scale:flags[unsafe_offset=25]=1
        barrier()
        if flags[unsafe_offset=25]==0:break
        if lane==0:
            var rhs=Array[Float64,8](fill=0)
            for i in range(count*2):rhs[i]=-evaluation.residual[i]
            var direction=linear8(evaluation.jacobian,rhs,count*2);work[unsafe_offset=5]+=1;work[unsafe_offset=7]+=Int64(direction.rank);work[unsafe_offset=8]=max(work[unsafe_offset=8],Int64(direction.rank))
            direction_value=direction.value.copy();flags[unsafe_offset=26]=Int32(1 if direction.valid else 0);flags[unsafe_offset=27]=0
        barrier()
        if flags[unsafe_offset=26]==0:break
        var factor=Float64(1)
        for _ in range(16):
            var next=x.copy()
            if lane==0:
                for i in range(count*2):next[i]+=factor*direction_value[i]
            var trial=evaluate_cooperative(nn,nt,tt,operators,valid,qn,qt,next,count,mu,normal_tolerance,False,shared,flags,debug,parallel)
            if lane==0:
                work[unsafe_offset=4]+=1;work[unsafe_offset=6]+=1
                if trial.valid and coupled_norm(trial.residual,count*2)<error:x=next^;flags[unsafe_offset=27]=1
                else:factor*=.5
            barrier()
            if flags[unsafe_offset=27]!=0:break
        if lane==0:work[unsafe_offset=3]+=1
        if flags[unsafe_offset=27]==0:break
    var final=evaluate_cooperative(nn,nt,tt,operators,valid,qn,qt,x,count,mu,normal_tolerance,False,shared,flags,debug,parallel)
    if lane==0:
        work[unsafe_offset=4]+=1
        flags[unsafe_offset=25]=Int32(1 if finish_cooperative(a,b,geometry,start,count,nn,operators,valid,impulses,targets,tangent,normal_tolerance,mu,c,s,work,metrics,patch,final,x) else 0)
    barrier()
    return flags[unsafe_offset=25]!=0

def fallback_leader(mut aa: BodyState,mut bb: BodyState,n: Vec3,k: Array[Float64,16],q: Array[Float64,4],cached: Array[Float64,256],valid: Array[Bool,16],start: Int,count: Int,patch: Int,geometry: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],mu: Float64,work: Pointer[Int64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin]):
    work[unsafe_offset=2]+=1
    var result=cached_normal_block(k,q,cached,valid,count,stats[unsafe_offset=5])
    if not result.valid:summary[unsafe_offset=0]=BR_BLOCK;return
    for i in range(count):
        var old=impulses[unsafe_offset=1+start+i];apply_normal(aa,bb,point(geometry,start+i),n,result.impulse[i]-old);impulses[unsafe_offset=1+start+i]=result.impulse[i]
    if mu>0:
        for i in range(count):
            var index=start+i;var p=point(geometry,index);var basis=cached_patch_basis(metrics,patch);var t=basis[0];var u=basis[1];var mass=cached_point_metric(metrics,index)
            if not finite(mass) or mass.x<=0 or mass.z<=0 or mass.x*mass.z-mass.y*mass.y<=0:summary[unsafe_offset=0]=BR_CONE;return
            var old_x=tangent[unsafe_offset=1+index*2];var old_y=tangent[unsafe_offset=2+index*2];var v=point_velocity(aa,bb,p)
            var free=Vec3(v.dot(t)-mass.x*old_x-mass.y*old_y,v.dot(u)-mass.y*old_x-mass.z*old_y,0)
            var next=disk_min(mass,free,mu*impulses[unsafe_offset=index+1])
            if not finite(next):summary[unsafe_offset=0]=BR_CONE;return
            apply_tangent(aa,bb,p,t*(next.x-old_x)+u*(next.y-old_y));tangent[unsafe_offset=1+index*2]=next.x;tangent[unsafe_offset=2+index*2]=next.y

def terminal_leader(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],mu: Float64,contacts: Int,pairs: Int,sweep: Int,flags: SharedInt):
    var residual=Float64(0);var friction_residual=Float64(0);var excess=Float64(0)
    var residual_patch=0
    for i in range(contacts):
        while residual_patch+1<pairs and i>=Int(spans[unsafe_offset=1+(residual_patch+1)*2]):residual_patch+=1
        var h=1+i*11;var aa=load(candidate,Int(headers[unsafe_offset=h+3]));var bb=load(candidate,Int(headers[unsafe_offset=h+8]));var n=normal(geometry,i);var p=point(geometry,i)
        var error=normal_speed(aa,bb,p,n)-targets[unsafe_offset=i+1];residual=max(residual,abs(error) if impulses[unsafe_offset=i+1]>0 else max(0.0,-error))
        if mu>0:
            var basis=cached_patch_basis(metrics,residual_patch);var t=basis[0];var u=basis[1];var mass=cached_point_metric(metrics,i);var x=tangent[unsafe_offset=1+i*2];var y=tangent[unsafe_offset=2+i*2];var v=point_velocity(aa,bb,p)
            var free=Vec3(v.dot(t)-mass.x*x-mass.y*y,v.dot(u)-mass.y*x-mass.z*y,0);var radius=mu*impulses[unsafe_offset=i+1];var optimum=disk_min(mass,free,radius)
            var dx=x-optimum.x;var dy=y-optimum.y;friction_residual=max(friction_residual,sqrt((mass.x*dx+mass.y*dy)**2+(mass.y*dx+mass.z*dy)**2));excess=max(excess,max(0.0,sqrt(x*x+y*y)-radius))
            if sqrt(x*x+y*y)>radius+1e-12*(1+radius):summary[unsafe_offset=0]=BR_CONE;return
    history[unsafe_offset=1+sweep*2]=residual;history[unsafe_offset=2+sweep*2]=friction_residual
    summary[unsafe_offset=1]=Int32(sweep+1);stats[unsafe_offset=2]=residual;stats[unsafe_offset=7]=friction_residual;stats[unsafe_offset=8]=excess
    flags[unsafe_offset=30]=Int32(1 if residual<=stats[unsafe_offset=5] and friction_residual<=stats[unsafe_offset=6] else 0)
def solve_box_compact_cooperative(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],grams: Pointer[Float64,MutAnyOrigin],operators: Pointer[Float64,MutAnyOrigin],mask_valid: Pointer[Int32,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],mu: Float64,iterations: Int32,c: Float64,s: Float64,work: Pointer[Int64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],parallel: Int32):
    if summary[unsafe_offset=0]!=0:return
    var shared=stack_allocation[506,DType.float64,address_space=AddressSpace.SHARED]()
    var flags=stack_allocation[32,DType.int32,address_space=AddressSpace.SHARED]()
    var lane=Int(thread_idx.x);var pairs=Int(summary[unsafe_offset=3]);var contacts=Int(summary[unsafe_offset=4])
    if lane==0:
        for i in range(32):flags[unsafe_offset=i]=-98765
        flags[unsafe_offset=28]=1;flags[unsafe_offset=30]=Int32(1 if pairs==0 else 0)
    barrier()
    for sweep in range(Int(iterations)):
        if pairs==0:break
        for patch in range(pairs):
            var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var h=1+start*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8])
            var aa=load(candidate,ia);var bb=load(candidate,ib);var n=normal(geometry,start);var k=Array[Float64,16](fill=0);var q=Array[Float64,4](fill=0)
            var cached=Array[Float64,256](fill=0);var valid=Array[Bool,16](fill=False)
            if lane==0:
                for i in range(count):
                    q[i]=normal_speed(aa,bb,point(geometry,start+i),n)-targets[unsafe_offset=1+start+i]
                    for j in range(count):
                        k[i*4+j]=grams[unsafe_offset=1+patch*16+i*4+j];q[i]-=k[i*4+j]*impulses[unsafe_offset=1+start+j]
                for mask in range(1<<count):
                    valid[mask]=mask_valid[unsafe_offset=1+patch*16+mask]!=0
                    for i in range(16):cached[mask*16+i]=operators[unsafe_offset=1+patch*256+mask*16+i]
            var accelerated=attempt_cooperative(aa,bb,geometry,start,count,k,cached,valid,impulses,targets,tangent,stats[unsafe_offset=5],mu,c,s,work,metrics,patch,shared,flags,debug,parallel!=0)
            if not accelerated:
                if lane==0:fallback_leader(aa,bb,n,k,q,cached,valid,start,count,patch,geometry,impulses,tangent,summary,stats,mu,work,metrics)
                barrier()
                if summary[unsafe_offset=0]!=0:return
            if lane==0:
                if not body_profile(aa) or not body_profile(bb):summary[unsafe_offset=0]=BR_PROFILE
                else:store(candidate,ia,aa);store(candidate,ib,bb)
            barrier()
            if summary[unsafe_offset=0]!=0:return
        if lane==0:terminal_leader(candidate,headers,geometry,spans,impulses,targets,tangent,summary,stats,history,metrics,mu,contacts,pairs,sweep,flags)
        barrier()
        if summary[unsafe_offset=0]!=0:return
    if lane==0:
        if flags[unsafe_offset=28]==0:summary[unsafe_offset=0]=BR_BLOCK
        elif flags[unsafe_offset=30]==0:summary[unsafe_offset=0]=BR_VELOCITY
        else:
            var energy=Float64(0)
            for i in range(CAPACITY):
                if touched[unsafe_offset=i+1]:energy+=kinetic(load(candidate,i))
            stats[unsafe_offset=1]=energy
            if not isfinite(energy) or energy>stats[unsafe_offset=0]+1e-9*(1+stats[unsafe_offset=0]):summary[unsafe_offset=0]=BR_ENERGY
    barrier()

def cached_patch_basis(metrics: Pointer[Float64,MutAnyOrigin],patch: Int) -> Tuple[Vec3,Vec3]:
    var base=1537+patch*6
    return Vec3(metrics[unsafe_offset=base],metrics[unsafe_offset=base+1],metrics[unsafe_offset=base+2]),Vec3(metrics[unsafe_offset=base+3],metrics[unsafe_offset=base+4],metrics[unsafe_offset=base+5])
def cached_point_metric(metrics: Pointer[Float64,MutAnyOrigin],point_index: Int) -> Vec3:
    var base=1633+point_index*3
    return Vec3(metrics[unsafe_offset=base],metrics[unsafe_offset=base+1],metrics[unsafe_offset=base+2])
