"""Opt-in resolve-local invariant NT/TT reuse; original solver remains available."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .core import BodyState,finite
from .kernels import load,store,CAPACITY
from .response_kernels import inv_mass,inv_inertia,kinetic,body_profile,normal,point,normal_speed,apply_normal
from .friction_kernels import tangent_axes,point_velocity,tangent_metric,disk_min,apply_tangent
from .box_response_math import cached_normal_block
from .coupled_friction_math import evaluate_coupled,linear8,coupled_norm
from .box_box_kernels import EPS
from .box_response_kernels import BR_BLOCK,BR_CONE,BR_PROFILE,BR_VELOCITY,BR_ENERGY

from .coupled_box_kernels import cross_metric


def coupled_attempt_cached(mut a: BodyState,mut b: BodyState,geometry: Pointer[Float64,MutAnyOrigin],start: Int,count: Int,nn: Array[Float64,16],operators: Array[Float64,256],valid: Array[Bool,16],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],normal_tolerance: Float64,mu: Float64,c: Float64,s: Float64,work: Pointer[Int64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],patch: Int) -> Bool:
    work[unsafe_offset=0]+=1
    var n=normal(geometry,start);var basis=tangent_axes(n,c,s);var t=basis[0];var u=basis[1]
    var nt=Array[Float64,32](fill=0);var tt=Array[Float64,64](fill=0);var qn=Array[Float64,4](fill=0);var qt=Array[Float64,8](fill=0);var x=Array[Float64,8](fill=0)
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
    for _ in range(8):
        var evaluation=evaluate_coupled(nn,nt,tt,operators,valid,qn,qt,x,count,mu,normal_tolerance,True);work[unsafe_offset=4]+=1
        if not evaluation.valid:break
        var error=coupled_norm(evaluation.residual,count*2);var scale=Float64(1)
        for i in range(count*2):scale=max(scale,abs(x[i]))
        if error<=64*EPS*scale:break
        var rhs=Array[Float64,8](fill=0)
        for i in range(count*2):rhs[i]=-evaluation.residual[i]
        var direction=linear8(evaluation.jacobian,rhs,count*2);work[unsafe_offset=5]+=1;work[unsafe_offset=7]+=Int64(direction.rank);work[unsafe_offset=8]=max(work[unsafe_offset=8],Int64(direction.rank))
        if not direction.valid:break
        var accepted=False;var factor=Float64(1)
        for _ in range(16):
            var next=x.copy()
            for i in range(count*2):next[i]+=factor*direction.value[i]
            var trial=evaluate_coupled(nn,nt,tt,operators,valid,qn,qt,next,count,mu,normal_tolerance,False);work[unsafe_offset=4]+=1;work[unsafe_offset=6]+=1
            if trial.valid and coupled_norm(trial.residual,count*2)<error:x=next^;accepted=True;break
            factor*=.5
        work[unsafe_offset=3]+=1
        if not accepted:break
    var final=evaluate_coupled(nn,nt,tt,operators,valid,qn,qt,x,count,mu,normal_tolerance,False);work[unsafe_offset=4]+=1
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

def solve_box_coupled_cached(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],grams: Pointer[Float64,MutAnyOrigin],operators: Pointer[Float64,MutAnyOrigin],mask_valid: Pointer[Int32,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],mu: Float64,iterations: Int32,c: Float64,s: Float64,work: Pointer[Int64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    var pairs=Int(summary[unsafe_offset=3]);var contacts=Int(summary[unsafe_offset=4]);var converged=pairs==0
    for sweep in range(Int(iterations)):
        if pairs==0:break
        for patch in range(pairs):
            var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var h=1+start*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8])
            var aa=load(candidate,ia);var bb=load(candidate,ib);var n=normal(geometry,start);var k=Array[Float64,16](fill=0);var q=Array[Float64,4](fill=0)
            for i in range(count):
                q[i]=normal_speed(aa,bb,point(geometry,start+i),n)-targets[unsafe_offset=1+start+i]
                for j in range(count):
                    k[i*4+j]=grams[unsafe_offset=1+patch*16+i*4+j];q[i]-=k[i*4+j]*impulses[unsafe_offset=1+start+j]
            var cached=Array[Float64,256](fill=0);var valid=Array[Bool,16](fill=False)
            for mask in range(1<<count):
                valid[mask]=mask_valid[unsafe_offset=1+patch*16+mask]!=0
                for i in range(16):cached[mask*16+i]=operators[unsafe_offset=1+patch*256+mask*16+i]
            var accelerated=coupled_attempt_cached(aa,bb,geometry,start,count,k,cached,valid,impulses,targets,tangent,stats[unsafe_offset=5],mu,c,s,work,metrics,patch)
            if not accelerated:
                work[unsafe_offset=2]+=1
                var result=cached_normal_block(k,q,cached,valid,count,stats[unsafe_offset=5])
                if not result.valid:summary[unsafe_offset=0]=BR_BLOCK;return
                for i in range(count):
                    var old=impulses[unsafe_offset=1+start+i];apply_normal(aa,bb,point(geometry,start+i),n,result.impulse[i]-old);impulses[unsafe_offset=1+start+i]=result.impulse[i]
                if mu>0:
                    for i in range(count):
                        var index=start+i;var p=point(geometry,index);var basis=tangent_axes(n,c,s);var t=basis[0];var u=basis[1];var mass=tangent_metric(aa,bb,p,t,u)
                        if not finite(mass) or mass.x<=0 or mass.z<=0 or mass.x*mass.z-mass.y*mass.y<=0:summary[unsafe_offset=0]=BR_CONE;return
                        var old_x=tangent[unsafe_offset=1+index*2];var old_y=tangent[unsafe_offset=2+index*2];var v=point_velocity(aa,bb,p)
                        var free=Vec3(v.dot(t)-mass.x*old_x-mass.y*old_y,v.dot(u)-mass.y*old_x-mass.z*old_y,0)
                        var next=disk_min(mass,free,mu*impulses[unsafe_offset=index+1])
                        if not finite(next):summary[unsafe_offset=0]=BR_CONE;return
                        apply_tangent(aa,bb,p,t*(next.x-old_x)+u*(next.y-old_y));tangent[unsafe_offset=1+index*2]=next.x;tangent[unsafe_offset=2+index*2]=next.y
            if not body_profile(aa) or not body_profile(bb):summary[unsafe_offset=0]=BR_PROFILE;return
            store(candidate,ia,aa);store(candidate,ib,bb)
        var residual=Float64(0);var friction_residual=Float64(0);var excess=Float64(0)
        for i in range(contacts):
            var h=1+i*11;var aa=load(candidate,Int(headers[unsafe_offset=h+3]));var bb=load(candidate,Int(headers[unsafe_offset=h+8]));var n=normal(geometry,i);var p=point(geometry,i)
            var error=normal_speed(aa,bb,p,n)-targets[unsafe_offset=i+1];residual=max(residual,abs(error) if impulses[unsafe_offset=i+1]>0 else max(0.0,-error))
            if mu>0:
                var basis=tangent_axes(n,c,s);var t=basis[0];var u=basis[1];var mass=tangent_metric(aa,bb,p,t,u);var x=tangent[unsafe_offset=1+i*2];var y=tangent[unsafe_offset=2+i*2];var v=point_velocity(aa,bb,p)
                var free=Vec3(v.dot(t)-mass.x*x-mass.y*y,v.dot(u)-mass.y*x-mass.z*y,0);var radius=mu*impulses[unsafe_offset=i+1];var optimum=disk_min(mass,free,radius)
                var dx=x-optimum.x;var dy=y-optimum.y;friction_residual=max(friction_residual,sqrt((mass.x*dx+mass.y*dy)**2+(mass.y*dx+mass.z*dy)**2));excess=max(excess,max(0.0,sqrt(x*x+y*y)-radius))
                if sqrt(x*x+y*y)>radius+1e-12*(1+radius):summary[unsafe_offset=0]=BR_CONE;return
        history[unsafe_offset=1+sweep*2]=residual;history[unsafe_offset=2+sweep*2]=friction_residual
        summary[unsafe_offset=1]=Int32(sweep+1);stats[unsafe_offset=2]=residual;stats[unsafe_offset=7]=friction_residual;stats[unsafe_offset=8]=excess
        converged=residual<=stats[unsafe_offset=5] and friction_residual<=stats[unsafe_offset=6]
    if not converged:summary[unsafe_offset=0]=BR_VELOCITY;return
    var energy=Float64(0)
    for i in range(CAPACITY):
        if touched[unsafe_offset=i+1]:energy+=kinetic(load(candidate,i))
    stats[unsafe_offset=1]=energy
    if not isfinite(energy) or energy>stats[unsafe_offset=0]+1e-9*(1+stats[unsafe_offset=0]):summary[unsafe_offset=0]=BR_ENERGY

def pack_coupled_metrics(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],c: Float64,s: Float64,metrics: Pointer[Float64,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    # Clear unused blocks/padding every successful setup; no previous resolve is trusted.
    for i in range(1536):metrics[unsafe_offset=i+1]=0
    for patch in range(Int(summary[unsafe_offset=3])):
        var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var h=1+start*11
        var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]))
        var n=normal(geometry,start);var basis=tangent_axes(n,c,s);var t=basis[0];var u=basis[1];var base=1+patch*96
        for i in range(count):
            var p=point(geometry,start+i)
            for j in range(count):
                var q=point(geometry,start+j)
                metrics[unsafe_offset=base+i*8+2*j]=cross_metric(a,b,p,n,q,t);metrics[unsafe_offset=base+i*8+2*j+1]=cross_metric(a,b,p,n,q,u)
                metrics[unsafe_offset=base+32+(2*i)*8+2*j]=cross_metric(a,b,p,t,q,t);metrics[unsafe_offset=base+32+(2*i)*8+2*j+1]=cross_metric(a,b,p,t,q,u)
                metrics[unsafe_offset=base+32+(2*i+1)*8+2*j]=cross_metric(a,b,p,u,q,t);metrics[unsafe_offset=base+32+(2*i+1)*8+2*j+1]=cross_metric(a,b,p,u,q,u)
