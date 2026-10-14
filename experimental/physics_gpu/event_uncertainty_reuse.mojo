"""Conditional interval transport/admission experiment; no opening-time advance."""
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3
from .supported_event_transition_reuse import supported_event_transition
from .single_support_advance import interval_arm,external_acc,support_arm
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,magnitude,fixed3,add3,scale3,cross3,norm3,next_up
comptime P = Pointer[Float64,MutAnyOrigin]

def store_bound(c: P,k: Int,a: Bound):c[unsafe_offset=k]=a.lo;c[unsafe_offset=k+1]=a.hi

def bound_energy(m: Float64,I: Float64,v: Bound3,w: Bound3) -> Bound:
    return times(point(.5),plus(times(point(m),plus(plus(square(v.x),square(v.y)),square(v.z))),times(point(I),plus(plus(square(w.x),square(w.y)),square(w.z)))))

def event_uncertainty(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    for k in range(192):output[unsafe_offset=k]=previous[unsafe_offset=k]
    for k in range(256):budget_output[unsafe_offset=k]=budget_previous[unsafe_offset=k]
    for k in range(128):report[unsafe_offset=k]=0
    for k in range(256):scratch[unsafe_offset=5200+k]=0
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    if request[unsafe_offset=11]!=0:status[unsafe_offset=0]=2000;return
    supported_event_transition(inputs,previous,request,scratch,scratch+192,status,report)
    report[unsafe_offset=0]=0
    if status[unsafe_offset=0]!=0:return
    var y=scratch+1120;var e=scratch+1472;var noise=scratch+1504;var b=scratch+1888;var c=scratch+5200;var rad=scratch+5500;var zero=scratch+5532
    var dt=scratch[unsafe_offset=130]-scratch[unsafe_offset=128];var acc=external_acc(inputs);var Vnorm=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]).length();var A=acc.length()+b[unsafe_offset=1]/inputs[unsafe_offset=1];var radius=b[unsafe_offset=5];var N=b[unsafe_offset=1];var W=b[unsafe_offset=3];var alpha=b[unsafe_offset=2];var selected=Int(inputs[unsafe_offset=40]);var event=Int(scratch[unsafe_offset=131]);var initial_arm=support_arm(inputs,y,selected)
    c[unsafe_offset=185]=dt;c[unsafe_offset=186]=N;c[unsafe_offset=187]=W;c[unsafe_offset=188]=alpha;c[unsafe_offset=189]=radius;c[unsafe_offset=190]=A;c[unsafe_offset=191]=Vnorm;c[unsafe_offset=192]=report[unsafe_offset=3]
    for j in range(21):
        var rate=Vnorm+A*dt if j<3 else A if j<6 else W if j<10 else alpha if j<13 else N if j==13 else radius*N if j<17 else N*1e-9
        if j>=18:
            var axis=j-18;var u=(axis+1)%3;var v=(axis+2)%3
            var pu=abs(y[unsafe_offset=u])+e[unsafe_offset=u]+noise[unsafe_offset=u]+Vnorm*dt+.5*A*dt*dt;var pv=abs(y[unsafe_offset=v])+e[unsafe_offset=v]+noise[unsafe_offset=v]+Vnorm*dt+.5*A*dt*dt
            var au=abs(acc.x if u==0 else acc.y if u==1 else acc.z);var av=abs(acc.x if v==0 else acc.y if v==1 else acc.z);rate=inputs[unsafe_offset=1]*(pu*av+pv*au)
            if axis!=1:
                var z=2 if axis==0 else 0;var ra=interval_arm(inputs,y,e,noise,selected);var rb=ra.z if z==2 else ra.x;var pc=magnitude(plus(widen(y[unsafe_offset=z],e[unsafe_offset=z]+noise[unsafe_offset=z]),rb))+Vnorm*dt+radius*W*dt+.5*A*dt*dt;rate+=pc*N
        # Preserve the old root-rate formula, conservatively pad its finite scalar arithmetic.
        var root_radius=next_up(dt*next_up(rate*(1+64*2.220446049250313e-16)))
        c[unsafe_offset=1+j]=e[unsafe_offset=j];c[unsafe_offset=22+j]=noise[unsafe_offset=j];c[unsafe_offset=43+j]=root_radius;rad[unsafe_offset=j]=next_up(e[unsafe_offset=j]+noise[unsafe_offset=j]+root_radius);c[unsafe_offset=64+j]=rad[unsafe_offset=j];zero[unsafe_offset=j]=0
        if not isfinite(rad[unsafe_offset=j]) or rad[unsafe_offset=j]<0:status[unsafe_offset=0]=2001;return
    var p=Bound3(widen(y[unsafe_offset=0],rad[unsafe_offset=0]),widen(y[unsafe_offset=1],rad[unsafe_offset=1]),widen(y[unsafe_offset=2],rad[unsafe_offset=2]));var v=Bound3(widen(y[unsafe_offset=3],rad[unsafe_offset=3]),widen(y[unsafe_offset=4],rad[unsafe_offset=4]),widen(y[unsafe_offset=5],rad[unsafe_offset=5]));var w=Bound3(widen(y[unsafe_offset=10],rad[unsafe_offset=10]),widen(y[unsafe_offset=11],rad[unsafe_offset=11]),widen(y[unsafe_offset=12],rad[unsafe_offset=12]));var r=interval_arm(inputs,y,rad,zero,event);var oldr=interval_arm(inputs,y,rad,zero,selected);var m=inputs[unsafe_offset=1];var I=inputs[unsafe_offset=2];var K=plus(divide(point(1),point(m)),divide(plus(square(r.x),square(r.z)),point(I)));var u=plus(v.y,cross3(w,r).y)
    if K.lo<=0 or u.hi>= -1e-9:status[unsafe_offset=0]=2002;return
    var impulse=divide(minus(point(0),u),K);var vn=add3(v,fixed3(0,0,0));vn.y=plus(v.y,divide(impulse,point(m)));var moment=cross3(r,Bound3(point(0),impulse,point(0)));var wn=add3(w,scale3(moment,divide(point(1),point(I))));var opened=plus(vn.y,cross3(wn,oldr).y);var held=plus(vn.y,cross3(wn,r).y);var q=plus(point(acc.y),cross3(wn,cross3(wn,r)).y);var reaction=point(0)
    var stable=impulse.lo>0 and opened.lo>1e-9 and magnitude(held)<=1e-9
    if scratch[unsafe_offset=98]==21:
        stable=stable and q.hi < -1e-9*(1+magnitude(q));reaction=divide(minus(point(0),q),K)
    elif scratch[unsafe_offset=98]==22:stable=stable and q.lo>1e-9*(1+magnitude(q))
    else:stable=False
    var loss=divide(square(u),times(point(2),K));store_bound(c,111,impulse);store_bound(c,113,loss);store_bound(c,115,q);store_bound(c,117,reaction);store_bound(c,119,opened);store_bound(c,121,held)
    var norm=point(0);var ratio=Float64(0);var limiting= -1
    for j in range(13):
        var interval=widen(y[unsafe_offset=j],rad[unsafe_offset=j]);var index=5+j if j<3 else 12+j-3 if j<6 else 8+j-6 if j<10 else 15+j-10
        if j>=3 and j<6:interval=vn.x if j==3 else vn.y if j==4 else vn.z
        elif j>=10:interval=wn.x if j==10 else wn.y if j==11 else wn.z
        store_bound(c,85+2*j,interval)
        var center=scratch[unsafe_offset=index];var delta=max(abs(interval.lo-center),abs(interval.hi-center));var B=1e-10*(1+min(abs(inputs[unsafe_offset=index]),abs(center)));var used=delta/(.25*B)
        if used>ratio:ratio=used;limiting=j
        c[unsafe_offset=200+j]=delta;c[unsafe_offset=213+j]=B
        if j>=6 and j<10:norm=plus(norm,square(interval))
    stable=stable and norm.lo>=1-1e-10 and norm.hi<=1+1e-10
    for j in range(8):
        var arm=interval_arm(inputs,y,rad,zero,j);var gap=minus(plus(p.y,arm.y),point(inputs[unsafe_offset=34]));var speed=plus(vn.y,cross3(wn,arm).y);store_bound(c,133+2*j,gap);store_bound(c,149+2*j,speed)
        if j==selected or j==event:stable=stable and magnitude(gap)<=1e-9
        else:stable=stable and gap.lo>1e-9
    var F=fixed3(acc.x*m,acc.y*m,acc.z*m);var ext=plus(plus(times(F.x,minus(p.x,point(inputs[unsafe_offset=5]))),times(F.y,minus(p.y,point(inputs[unsafe_offset=6])))),times(F.z,minus(p.z,point(inputs[unsafe_offset=7]))));var T0=bound_energy(m,I,fixed3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),fixed3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]));var deltaE=minus(bound_energy(m,I,vn,wn),T0);var work=widen(y[unsafe_offset=17],rad[unsafe_offset=17]);var ideal=plus(minus(deltaE,ext),loss);var residual=minus(ideal,work);var EB=1e-9*(1+T0.lo)
    store_bound(c,123,residual);store_bound(c,125,ideal);c[unsafe_offset=127]=EB;c[unsafe_offset=128]=y[unsafe_offset=17];c[unsafe_offset=129]=scratch[unsafe_offset=104];c[unsafe_offset=130]=ratio;c[unsafe_offset=131]=Float64(limiting);c[unsafe_offset=132]=1 if stable else 0;store_bound(c,165,work);store_bound(c,167,ext);store_bound(c,169,deltaE);store_bound(c,171,norm)
    var time=Bound(scratch[unsafe_offset=128],scratch[unsafe_offset=130]);var J=add3(scale3(F,time),Bound3(point(0),plus(widen(y[unsafe_offset=13],rad[unsafe_offset=13]),impulse),point(0)));var M=add3(Bound3(widen(y[unsafe_offset=14],rad[unsafe_offset=14]),widen(y[unsafe_offset=15],rad[unsafe_offset=15]),widen(y[unsafe_offset=16],rad[unsafe_offset=16])),moment);var origin=add3(Bound3(widen(y[unsafe_offset=18],rad[unsafe_offset=18]),widen(y[unsafe_offset=19],rad[unsafe_offset=19]),widen(y[unsafe_offset=20],rad[unsafe_offset=20])),cross3(add3(p,r),Bound3(point(0),impulse,point(0))))
    var ledger_ratio=Float64(0)
    for j in range(9):
        var a=J.x if j==0 else J.y if j==1 else J.z if j==2 else M.x if j==3 else M.y if j==4 else M.z if j==5 else origin.x if j==6 else origin.y if j==7 else origin.z
        store_bound(c,226+2*j,a);var center=scratch[unsafe_offset=149+j];var debt=max(abs(a.lo-center),abs(a.hi-center));ledger_ratio=max(ledger_ratio,debt/(.25e-10))
    c[unsafe_offset=244]=ledger_ratio;report[unsafe_offset=71]=ledger_ratio
    c[unsafe_offset=0]=1;report[unsafe_offset=64]=ratio;report[unsafe_offset=65]=Float64(limiting);report[unsafe_offset=66]=1 if stable else 0;report[unsafe_offset=67]=magnitude(residual)/EB;report[unsafe_offset=68]=(magnitude(work)+magnitude(residual))/EB;report[unsafe_offset=69]=magnitude(ideal)/EB
    if not stable:status[unsafe_offset=0]=2003;return
    if ratio>1 or ledger_ratio>1 or magnitude(work)+magnitude(residual)>EB or magnitude(ideal)>EB:status[unsafe_offset=0]=2004;return
    # A passing certificate still advances no opening-window time.
    for j in range(192):output[unsafe_offset=j]=scratch[unsafe_offset=j]
    for j in range(256):budget_output[unsafe_offset=j]=c[unsafe_offset=j]
    report[unsafe_offset=70]=1
