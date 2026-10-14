"""Private per-macro immutable-matrix row-bound cache; upper recurrence is unchanged."""
from std.memory import Pointer
from max.gpu import thread_idx
from max.gpu.sync import barrier
from std.math import isfinite
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,magnitude,add3,scale3,cross3,fixed3,next_up
from .event_centered_map import jarm
comptime P = Pointer[Float64,MutAnyOrigin]
def dot3(a: Bound3,b: Bound3) -> Bound:return plus(plus(times(a.x,b.x),times(a.y,b.y)),times(a.z,b.z))
def load3(y: P,r: P,k: Int) -> Bound3:return Bound3(widen(y[unsafe_offset=k],r[unsafe_offset=k]),widen(y[unsafe_offset=k+1],r[unsafe_offset=k+1]),widen(y[unsafe_offset=k+2],r[unsafe_offset=k+2]))
def store3(A: P,row: Int,col: Int,v: Bound3):
    A[unsafe_offset=row*21+col]=next_up(magnitude(v.x));A[unsafe_offset=(row+1)*21+col]=next_up(magnitude(v.y));A[unsafe_offset=(row+2)*21+col]=next_up(magnitude(v.z))
def component_matrix(x: P,y: P,tube: P,A: P,seed: P) -> Int:
    for i in range(441):A[unsafe_offset=i]=0
    for i in range(22):seed[unsafe_offset=i]=0
    for i in range(21):
        if not isfinite(y[unsafe_offset=i]) or not isfinite(tube[unsafe_offset=i]) or tube[unsafe_offset=i]<0:return 2300
    if x[unsafe_offset=1]<=0 or x[unsafe_offset=2]<=0 or x[unsafe_offset=2]!=x[unsafe_offset=3] or x[unsafe_offset=2]!=x[unsafe_offset=4] or x[unsafe_offset=35]!=0 or x[unsafe_offset=36]!=0 or x[unsafe_offset=40]<0 or x[unsafe_offset=40]>7 or x[unsafe_offset=40]!=Float64(Int(x[unsafe_offset=40])):return 2300
    var norm=point(0)
    for j in range(6,10):norm=plus(norm,square(widen(y[unsafe_offset=j],tube[unsafe_offset=j])))
    if norm.lo<=0:return 2301
    var ar=jarm(x,y,tube,seed,Int(x[unsafe_offset=40]));var r=Bound3(ar.x.v,ar.y.v,ar.z.v);var p=load3(y,tube,0);var w=load3(y,tube,10);var qv=load3(y,tube,6);var qw=widen(y[unsafe_offset=9],tube[unsafe_offset=9]);var m=point(x[unsafe_offset=1]);var I=point(x[unsafe_offset=2]);var ae=Bound3(plus(divide(point(x[unsafe_offset=18]),m),point(x[unsafe_offset=42])),plus(divide(point(x[unsafe_offset=19]),m),point(x[unsafe_offset=43])),plus(divide(point(x[unsafe_offset=20]),m),point(x[unsafe_offset=44])));var F=scale3(ae,m);var K=plus(divide(point(1),m),divide(plus(square(r.x),square(r.z)),I));var c=cross3(w,r);var q=plus(ae.y,cross3(w,c).y);var N=divide(minus(point(0),q),K)
    if K.lo<=0 or N.lo<=0 or not isfinite(N.hi):return 2301
    var force=Bound3(point(0),N,point(0));var u=plus(widen(y[unsafe_offset=4],tube[unsafe_offset=4]),c.y)
    for k in range(13):
        var dp=fixed3(Float64(k==0),Float64(k==1),Float64(k==2));var dv=fixed3(Float64(k==3),Float64(k==4),Float64(k==5));var dw=fixed3(Float64(k==10),Float64(k==11),Float64(k==12));var dqv=fixed3(Float64(k==6),Float64(k==7),Float64(k==8));var dqw=point(Float64(k==9));var dr=fixed3(0,0,0)
        if k>=6 and k<10:
            seed[unsafe_offset=k]=1
            var derivative=jarm(x,y,tube,seed,Int(x[unsafe_offset=40]));dr=Bound3(derivative.x.d,derivative.y.d,derivative.z.d);seed[unsafe_offset=k]=0
        var dc=add3(cross3(dw,r),cross3(w,dr));var dcc=add3(cross3(dw,c),cross3(w,dc));var dK=divide(plus(times(times(point(2),r.x),dr.x),times(times(point(2),r.z),dr.z)),I);var dN=divide(minus(minus(point(0),dcc.y),times(N,dK)),K);var df=Bound3(point(0),dN,point(0));var dm=add3(cross3(dr,force),cross3(r,df));var dquat=scale3(add3(add3(scale3(dw,qw),scale3(w,dqw)),add3(cross3(dw,qv),cross3(w,dqv))),point(.5));var du=plus(dv.y,dc.y);var dwork=plus(times(dN,u),times(N,du));var dorigin=add3(cross3(dp,F),add3(cross3(add3(dp,dr),force),cross3(add3(p,r),df)))
        store3(A,0,k,dv);store3(A,3,k,scale3(df,divide(point(1),m)));store3(A,6,k,dquat);A[unsafe_offset=9*21+k]=next_up(magnitude(times(point(-.5),plus(dot3(dw,qv),dot3(w,dqv)))));store3(A,10,k,scale3(dm,divide(point(1),I)));A[unsafe_offset=13*21+k]=next_up(magnitude(dN));store3(A,14,k,dm);A[unsafe_offset=17*21+k]=next_up(magnitude(dwork));store3(A,18,k,dorigin)
    for j in range(441):
        if not isfinite(A[unsafe_offset=j]) or A[unsafe_offset=j]<0:return 2301
    return 0

def admission(A: P,r: P,h: Float64,u: P,temp: P,steps: Int,report: P,cache: P,work: P) -> Int:
    if not isfinite(h) or h<=0 or h>1.0/30 or steps<1 or steps>16:return 2300
    var reuse=cache[unsafe_offset=0]==h
    var qmax=cache[unsafe_offset=1] if reuse else Float64(0);var rmax=Float64(0)
    for i in range(21):
        if not isfinite(r[unsafe_offset=i]) or r[unsafe_offset=i]<0:return 2300
        u[unsafe_offset=i]=r[unsafe_offset=i];rmax=max(rmax,r[unsafe_offset=i])
        if not reuse:
            var row=Float64(0)
            for j in range(21):
                var v=A[unsafe_offset=i*21+j]
                if not isfinite(v) or v<0:return 2300
                row=next_up(row+v)
            qmax=max(qmax,next_up(h*row))
    if not reuse:
        cache[unsafe_offset=0]=h;cache[unsafe_offset=1]=qmax
    report[unsafe_offset=0]=qmax
    if qmax>=1:return 2302
    work[unsafe_offset=1]=rmax;work[unsafe_offset=2]=qmax
    return 0

def component_enclose(A: P,r: P,h: Float64,u: P,temp: P,steps: Int,report: P,cache: P,work: P) -> Int:
    var lane=Int(thread_idx.x)
    if lane==0:work[unsafe_offset=0]=Float64(admission(A,r,h,u,temp,steps,report,cache,work))
    barrier()
    if work[unsafe_offset=0]!=0:return Int(work[unsafe_offset=0])
    for iteration in range(steps):
        if lane<21:
            var v=Float64(0)
            for j in range(21):v=next_up(v+next_up(A[unsafe_offset=lane*21+j]*u[unsafe_offset=j]))
            temp[unsafe_offset=lane]=next_up(r[unsafe_offset=lane]+next_up(h*v))
        barrier()
        if lane<21:u[unsafe_offset=lane]=temp[unsafe_offset=lane]
        barrier()
    if lane<21:
        var v=Float64(0)
        for j in range(21):v=next_up(v+next_up(A[unsafe_offset=lane*21+j]*u[unsafe_offset=j]))
        work[unsafe_offset=8+lane]=next_up(next_up(r[unsafe_offset=lane]+next_up(h*v))-u[unsafe_offset=lane])
    barrier()
    if lane==0:
        var residual=Float64(0)
        for i in range(21):residual=max(residual,work[unsafe_offset=8+i])
        var qmax=work[unsafe_offset=2];var rmax=work[unsafe_offset=1]
        work[unsafe_offset=3]=plus(times(point(2),divide(point(residual),minus(point(1),point(qmax)))),times(point(64*2.220446049250313e-16),point(rmax))).hi
    barrier()
    if lane<21:u[unsafe_offset=lane]=plus(point(u[unsafe_offset=lane]),point(work[unsafe_offset=3])).hi
    barrier()
    if lane<21:
        var v=Float64(0)
        for j in range(21):v=next_up(v+next_up(A[unsafe_offset=lane*21+j]*u[unsafe_offset=j]))
        work[unsafe_offset=8+lane]=next_up(r[unsafe_offset=lane]+next_up(h*v))
    barrier()
    if lane==0:
        var slack=Float64(1e30)
        for i in range(21):
            var required=work[unsafe_offset=8+i]
            if not isfinite(u[unsafe_offset=i]) or u[unsafe_offset=i]<required:
                work[unsafe_offset=0]=2303;break
            slack=min(slack,u[unsafe_offset=i]-required)
        if work[unsafe_offset=0]==0:report[unsafe_offset=1]=slack
    barrier()
    return Int(work[unsafe_offset=0])
