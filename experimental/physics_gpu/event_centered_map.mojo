"""Interval forward derivatives of the unchanged single-active event map."""
from std.memory import Pointer
from .support_intervals import Bound,point,widen,plus,minus,times,divide,square,root
comptime P = Pointer[Float64,MutAnyOrigin]
@fieldwise_init
struct Jet(ImplicitlyCopyable,Movable):
    var v: Bound
    var d: Bound
@fieldwise_init
struct Jet3(ImplicitlyCopyable,Movable):
    var x: Jet
    var y: Jet
    var z: Jet

def jc(x: Float64) -> Jet:return Jet(point(x),point(0))
def ja(a: Jet,b: Jet) -> Jet:return Jet(plus(a.v,b.v),plus(a.d,b.d))
def js(a: Jet,b: Jet) -> Jet:return Jet(minus(a.v,b.v),minus(a.d,b.d))
def jm(a: Jet,b: Jet) -> Jet:return Jet(times(a.v,b.v),plus(times(a.d,b.v),times(a.v,b.d)))
def jd(a: Jet,b: Jet) -> Jet:
    var q=divide(a.v,b.v)
    return Jet(q,divide(minus(a.d,times(q,b.d)),b.v))
def j2(a: Jet) -> Jet:return Jet(square(a.v),times(times(point(2),a.v),a.d))
def jr(a: Jet) -> Jet:
    var s=root(a.v)
    return Jet(s,divide(a.d,times(point(2),s)))
def jadd(a: Jet3,b: Jet3) -> Jet3:return Jet3(ja(a.x,b.x),ja(a.y,b.y),ja(a.z,b.z))
def jscale(a: Jet3,b: Jet) -> Jet3:return Jet3(jm(a.x,b),jm(a.y,b),jm(a.z,b))
def jcross(a: Jet3,b: Jet3) -> Jet3:return Jet3(js(jm(a.y,b.z),jm(a.z,b.y)),js(jm(a.z,b.x),jm(a.x,b.z)),js(jm(a.x,b.y),jm(a.y,b.x)))
def jdot(a: Jet3,b: Jet3) -> Jet:return ja(ja(jm(a.x,b.x),jm(a.y,b.y)),jm(a.z,b.z))
def jnorm2(a: Jet3) -> Jet:return ja(ja(j2(a.x),j2(a.y)),j2(a.z))
def jrotate(qx: Jet,qy: Jet,qz: Jet,qw: Jet,v: Jet3) -> Jet3:
    var norm=jr(ja(ja(j2(qx),j2(qy)),ja(j2(qz),j2(qw))));var q=Jet3(jd(qx,norm),jd(qy,norm),jd(qz,norm));var w=jd(qw,norm);var t=jscale(jcross(q,v),jc(2))
    return jadd(v,jadd(jscale(t,w),jcross(q,t)))
def jload(y: P,r: P,seed: P,k: Int) -> Jet:return Jet(widen(y[unsafe_offset=k],r[unsafe_offset=k]),point(seed[unsafe_offset=k]))
def jload3(y: P,r: P,seed: P,k: Int) -> Jet3:return Jet3(jload(y,r,seed,k),jload(y,r,seed,k+1),jload(y,r,seed,k+2))
def jarm(x: P,y: P,r: P,seed: P,i: Int) -> Jet3:
    var corner=Jet3(jc(-x[unsafe_offset=24] if i%2==0 else x[unsafe_offset=24]),jc(-x[unsafe_offset=25] if (i//2)%2==0 else x[unsafe_offset=25]),jc(-x[unsafe_offset=26] if (i//4)%2==0 else x[unsafe_offset=26]));var local=jadd(Jet3(jc(x[unsafe_offset=27]),jc(x[unsafe_offset=28]),jc(x[unsafe_offset=29])),jrotate(jc(x[unsafe_offset=30]),jc(x[unsafe_offset=31]),jc(x[unsafe_offset=32]),jc(x[unsafe_offset=33]),corner))
    return jrotate(jload(y,r,seed,6),jload(y,r,seed,7),jload(y,r,seed,8),jload(y,r,seed,9),local)
def jenergy(m: Jet,I: Jet,v: Jet3,w: Jet3) -> Jet:return jm(jc(.5),ja(jm(m,jnorm2(v)),jm(I,jnorm2(w))))
def jout(destination: P,k: Int,a: Jet):
    destination[unsafe_offset=4*k]=a.v.lo;destination[unsafe_offset=4*k+1]=a.v.hi;destination[unsafe_offset=4*k+2]=a.d.lo;destination[unsafe_offset=4*k+3]=a.d.hi
def jout3(destination: P,k: Int,a: Jet3):jout(destination,k,a.x);jout(destination,k+1,a.y);jout(destination,k+2,a.z)

def centered_map(x: P,y: P,radii: P,seed: P,tlo: Float64,thi: Float64,new_id: Int,phase: Int,destination: P):
    var p=jload3(y,radii,seed,0);var v=jload3(y,radii,seed,3);var w=jload3(y,radii,seed,10);var m=jc(x[unsafe_offset=1]);var I=jc(x[unsafe_offset=2]);var n=Jet3(jc(0),jc(1),jc(0));var arm=jarm(x,y,radii,seed,new_id);var oldarm=jarm(x,y,radii,seed,Int(x[unsafe_offset=40]));var K=ja(jd(jc(1),m),jd(ja(j2(arm.x),j2(arm.z)),I));var u=ja(v.y,jcross(w,arm).y);var lam=jd(js(jc(0),u),K);var J=jscale(n,lam);var moment=jcross(arm,J);var vp=jadd(v,jscale(J,jd(jc(1),m)));var wp=jadd(w,jscale(moment,jd(jc(1),I)));var ae=Jet3(ja(jd(jc(x[unsafe_offset=18]),m),jc(x[unsafe_offset=42])),ja(jd(jc(x[unsafe_offset=19]),m),jc(x[unsafe_offset=43])),ja(jd(jc(x[unsafe_offset=20]),m),jc(x[unsafe_offset=44])));var F=jscale(ae,m);var q=ja(ae.y,jcross(wp,jcross(wp,arm)).y);var N=jd(js(jc(0),q),K) if phase==21 else jc(0);var loss=jd(j2(u),jm(jc(2),K));var T=jenergy(m,I,vp,wp);var T0=jenergy(m,I,Jet3(jc(x[unsafe_offset=12]),jc(x[unsafe_offset=13]),jc(x[unsafe_offset=14])),Jet3(jc(x[unsafe_offset=15]),jc(x[unsafe_offset=16]),jc(x[unsafe_offset=17])));var displacement=jadd(p,Jet3(jc(-x[unsafe_offset=5]),jc(-x[unsafe_offset=6]),jc(-x[unsafe_offset=7])));var external=jdot(F,displacement);var work=jload(y,radii,seed,17);var ideal=ja(js(js(T,T0),external),loss)
    jout3(destination,0,p);jout3(destination,3,vp)
    for k in range(4):jout(destination,6+k,jload(y,radii,seed,6+k))
    jout3(destination,10,wp);jout(destination,13,lam);jout(destination,14,loss);jout(destination,15,N);jout(destination,16,q);jout(destination,17,ja(vp.y,jcross(wp,oldarm).y));jout(destination,18,ja(vp.y,jcross(wp,arm).y))
    for k in range(8):jout(destination,19+k,js(ja(p.y,jarm(x,y,radii,seed,k).y),jc(x[unsafe_offset=34])))
    var norm=jc(0)
    for k in range(6,10):norm=ja(norm,j2(jload(y,radii,seed,k)))
    jout(destination,27,norm);jout(destination,28,external);jout(destination,29,T);jout(destination,30,js(ideal,work));jout(destination,31,ideal)
    var time=Jet(Bound(tlo,thi),point(seed[unsafe_offset=21]));var totalJ=jadd(jadd(jscale(F,time),jscale(n,jload(y,radii,seed,13))),J);var totalM=jadd(jload3(y,radii,seed,14),moment);var totalO=jadd(jload3(y,radii,seed,18),jcross(jadd(p,arm),J))
    jout3(destination,32,totalJ);jout3(destination,35,totalM);jout3(destination,38,totalO);jout(destination,41,work)
    var A=ja(jd(jc(1),m),jd(ja(j2(oldarm.x),j2(oldarm.z)),I));var B=ja(jd(jc(1),m),jd(ja(jm(oldarm.x,arm.x),jm(oldarm.z,arm.z)),I));var AC=jm(A,K)
    jout(destination,42,jd(js(AC,j2(B)),AC));jout(destination,43,u);jout(destination,44,ja(v.y,jcross(w,oldarm).y))

def centered_rhs(x: P,y: P,radii: P,seed: P,destination: P):
    var p=jload3(y,radii,seed,0);var v=jload3(y,radii,seed,3);var w=jload3(y,radii,seed,10);var qv=jload3(y,radii,seed,6);var qw=jload(y,radii,seed,9);var m=jc(x[unsafe_offset=1]);var I=jc(x[unsafe_offset=2]);var arm=jarm(x,y,radii,seed,Int(x[unsafe_offset=40]));var ae=Jet3(ja(jd(jc(x[unsafe_offset=18]),m),jc(x[unsafe_offset=42])),ja(jd(jc(x[unsafe_offset=19]),m),jc(x[unsafe_offset=43])),ja(jd(jc(x[unsafe_offset=20]),m),jc(x[unsafe_offset=44])));var K=ja(jd(jc(1),m),jd(ja(j2(arm.x),j2(arm.z)),I));var N=jd(js(jc(0),ja(ae.y,jcross(w,jcross(w,arm)).y)),K);var force=Jet3(jc(0),N,jc(0));var torque=jcross(arm,force);var a=jadd(ae,jscale(force,jd(jc(1),m)));var alpha=jscale(torque,jd(jc(1),I));var qdot=jscale(jadd(jscale(w,qw),jcross(w,qv)),jc(.5));var origin=jadd(jcross(p,jscale(ae,m)),jcross(jadd(p,arm),force))
    jout3(destination,0,v);jout3(destination,3,a);jout3(destination,6,qdot);jout(destination,9,jm(jc(-.5),jdot(w,qv)));jout3(destination,10,alpha);jout(destination,13,N);jout3(destination,14,torque);jout(destination,17,jm(N,ja(v.y,jcross(w,arm).y)));jout3(destination,18,origin)
