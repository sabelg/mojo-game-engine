"""Whole-cell geometry and analytic support-RHS derivative row bounds."""
from std.memory import Pointer
from std.math import isfinite,sqrt
from .single_support_advance import interval_arm,interval_local,external_acc
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,root,magnitude,fixed3,add3,scale3,cross3,norm3,rotate3,next_up
comptime P = Pointer[Float64,MutAnyOrigin]
def opening_bounds(x: P,y: P,h: Float64,e: P,r: P,bounds: P,released: Int) -> Int:
    var selected=Int(x[unsafe_offset=40]);var arm=interval_arm(x,y,e,r,selected);var vy=widen(y[unsafe_offset=4],e[unsafe_offset=4]+r[unsafe_offset=4]);var py=widen(y[unsafe_offset=1],e[unsafe_offset=1]+r[unsafe_offset=1]);var w=Bound3(widen(y[unsafe_offset=10],e[unsafe_offset=10]+r[unsafe_offset=10]),widen(y[unsafe_offset=11],e[unsafe_offset=11]+r[unsafe_offset=11]),widen(y[unsafe_offset=12],e[unsafe_offset=12]+r[unsafe_offset=12]));var gap=minus(plus(py,arm.y),point(x[unsafe_offset=34]));var vn=plus(vy,cross3(w,arm).y)
    var drift=plus(gap,times(Bound(0,h),vn));bounds[unsafe_offset=0]=magnitude(drift);bounds[unsafe_offset=1]=magnitude(vn)
    if not isfinite(drift.lo) or not isfinite(drift.hi) or magnitude(drift)>1e-9 or magnitude(vn)>1e-9:return 1502
    var ae=plus(divide(point(x[unsafe_offset=19]),point(x[unsafe_offset=1])),point(x[unsafe_offset=43]));var rs=norm3(interval_local(x,selected)).hi;var w0=norm3(w).hi;var W=min(sqrt(300.0),next_up(w0+max(1.0,w0*.5)));var W2=times(point(W),point(W));var nmax=times(point(x[unsafe_offset=1]),plus(point(magnitude(ae)),times(W2,point(rs))));var alpha=divide(times(point(rs),nmax),point(x[unsafe_offset=2]));var q=plus(ae,cross3(w,cross3(w,arm)).y)
    var qdot=times(point(rs),plus(times(point(2*W),alpha),times(W2,point(W))));var qupper=plus(q,times(point(h),qdot)).hi
    bounds[unsafe_offset=2]=qupper;bounds[unsafe_offset=3]=1e30
    if True and (plus(point(w0),times(point(h),alpha)).hi>W or qupper>=0):return 1504
    var aevec=external_acc(x)
    for axis in range(3):
        var ak=magnitude(plus(divide(point(x[unsafe_offset=18+axis]),point(x[unsafe_offset=1])),point(x[unsafe_offset=42+axis])))
        var av=plus(point(ak),divide(nmax,point(x[unsafe_offset=1]))) if axis==1 and True else point(ak)
        var vbound=plus(point(abs(y[unsafe_offset=3+axis])+e[unsafe_offset=3+axis]+r[unsafe_offset=3+axis]),times(point(h),av)).hi
        var pbound=plus(plus(point(abs(y[unsafe_offset=axis])+e[unsafe_offset=axis]+r[unsafe_offset=axis]),times(point(h),point(abs(y[unsafe_offset=3+axis])+e[unsafe_offset=3+axis]+r[unsafe_offset=3+axis]))),times(times(point(.5),square(point(h))),av)).hi
        var wbound=plus(point(abs(y[unsafe_offset=10+axis])+e[unsafe_offset=10+axis]+r[unsafe_offset=10+axis]),times(point(h),alpha)).hi if True else Float64(0)
        if vbound>20 or pbound>1000 or wbound>10 or av.hi>1000 or (True and alpha.hi>1000):return 1503
    bounds[unsafe_offset=4]=1e30
    for j in range(8):
        if j==selected:continue
        var a=interval_arm(x,y,e,r,j);var g=minus(plus(py,a.y),point(x[unsafe_offset=34]));var speed=plus(vy,cross3(w,a).y);var radius=norm3(interval_local(x,j)).hi;var accel=plus(plus(point(magnitude(ae)),divide(nmax,point(x[unsafe_offset=1]))),plus(times(alpha,point(radius)),times(W2,point(radius))));var end=minus(plus(g,times(speed,point(h))),times(times(point(.5),square(point(h))),accel));var low=min(g.lo,end.lo) if True else g.lo
        if j==released:
            var opening=minus(speed,times(point(h),accel)).lo
            bounds[unsafe_offset=4]=opening
            if g.lo< -1e-9 or opening<=0:return 2204
            continue
        bounds[unsafe_offset=3]=min(bounds[unsafe_offset=3],low)
        if not isfinite(low) or low<=1e-9:return 1504
    return 0

def support_row_bounds(x: P,y: P,r: P,zero: P,normal_max: Float64,L: P) -> Float64:
    var q2=point(0)
    for k in range(6,10):q2=plus(q2,square(widen(y[unsafe_offset=k],r[unsafe_offset=k])))
    var qn=root(q2);var radius=point(norm3(interval_local(x,Int(x[unsafe_offset=40]))).hi);var w=Bound3(widen(y[unsafe_offset=10],r[unsafe_offset=10]),widen(y[unsafe_offset=11],r[unsafe_offset=11]),widen(y[unsafe_offset=12],r[unsafe_offset=12]));var W=point(norm3(w).hi);var Rq=divide(times(point(4),radius),point(qn.lo));var s3=root(point(3));var mass=point(x[unsafe_offset=1]);var I=point(x[unsafe_offset=2]);var N=point(normal_max)
    var LN=plus(times(mass,plus(times(times(times(point(2),W),radius),s3),times(square(W),Rq))),times(times(times(times(N,mass),point(2)),radius),divide(Rq,I)))
    var torque=plus(times(Rq,N),times(radius,LN));var Qrate=times(point(.5),plus(times(s3,point(qn.hi)),times(point(2),W)))
    var arm=interval_arm(x,y,r,zero,Int(x[unsafe_offset=40]));var vn=plus(widen(y[unsafe_offset=4],r[unsafe_offset=4]),cross3(w,arm).y);var Lu=plus(point(1),plus(times(s3,radius),times(W,Rq)));var work=plus(times(LN,point(magnitude(vn))),times(N,Lu))
    var p=Bound3(widen(y[unsafe_offset=0],r[unsafe_offset=0]),widen(y[unsafe_offset=1],r[unsafe_offset=1]),widen(y[unsafe_offset=2],r[unsafe_offset=2]));var a=Bound3(plus(divide(point(x[unsafe_offset=18]),mass),point(x[unsafe_offset=42])),plus(divide(point(x[unsafe_offset=19]),mass),point(x[unsafe_offset=43])),plus(divide(point(x[unsafe_offset=20]),mass),point(x[unsafe_offset=44])));var origin=plus(plus(times(times(s3,mass),point(norm3(a).hi)),times(plus(s3,Rq),N)),times(point(norm3(add3(p,arm)).hi),LN))
    var largest=Float64(0)
    for j in range(21):
        var value=Float64(0)
        if j<3:value=1
        elif j==4:value=divide(LN,mass).hi
        elif j>=6 and j<=9:value=Qrate.hi
        elif j==10 or j==12:value=divide(torque,I).hi
        elif j==13:value=LN.hi
        elif j==14 or j==16:value=torque.hi
        elif j==17:value=work.hi
        elif j>=18:value=origin.hi
        L[unsafe_offset=j]=value;largest=max(largest,value)
    return largest
