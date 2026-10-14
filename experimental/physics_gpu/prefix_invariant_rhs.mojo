"""Within-DP-call reuse of fixed shape/force inputs; fresh stage reaction geometry."""
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import component,finite
from .single_support_advance import DIM,local_corner,external_acc,dp_a,dp_b
comptime P=Pointer[Float64,MutAnyOrigin]
def invariant_rhs(x: P,y: P,d: P,corner: Vec3,ae: Vec3,invmass: Float64,invinertia: Float64) -> Int:
    for k in range(DIM):
        if not isfinite(y[unsafe_offset=k]):return 1503
    var p=Vec3(y[unsafe_offset=0],y[unsafe_offset=1],y[unsafe_offset=2]);var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var qv=Vec3(y[unsafe_offset=6],y[unsafe_offset=7],y[unsafe_offset=8]);var qw=y[unsafe_offset=9];var qnorm=qv.dot(qv)+qw*qw
    if component(p)>1000 or component(v)>20 or component(w)>10 or qnorm<.25 or qnorm>4:return 1503
    var r=Quaternion(y[unsafe_offset=6],y[unsafe_offset=7],y[unsafe_offset=8],y[unsafe_offset=9]).rotate(corner);var mass=x[unsafe_offset=1];var inertia=x[unsafe_offset=2];var K=invmass+(r.x*r.x+r.z*r.z)/inertia;var free=ae.y+w.cross(w.cross(r)).y;var N=-free/K
    if not isfinite(N) or N<=0:return 1504
    var force=Vec3(0,N,0);var torque=r.cross(force);var alpha=torque*invinertia;var a=ae+force*invmass;var qdot=(w*qw+w.cross(qv))*.5;var origin=p.cross(ae*mass)+(p+r).cross(force)
    if not finite(a) or not finite(alpha) or component(a)>1000 or component(alpha)>1000:return 1503
    for k in range(3):
        d[unsafe_offset=k]=v.x if k==0 else v.y if k==1 else v.z;d[unsafe_offset=3+k]=a.x if k==0 else a.y if k==1 else a.z;d[unsafe_offset=6+k]=qdot.x if k==0 else qdot.y if k==1 else qdot.z;d[unsafe_offset=10+k]=alpha.x if k==0 else alpha.y if k==1 else alpha.z;d[unsafe_offset=14+k]=torque.x if k==0 else torque.y if k==1 else torque.z;d[unsafe_offset=18+k]=origin.x if k==0 else origin.y if k==1 else origin.z
    d[unsafe_offset=9]=-.5*w.dot(qv);d[unsafe_offset=13]=N;d[unsafe_offset=17]=N*(v+w.cross(r)).y
    return 0

def dp_step(x: P,y: P,h: Float64,dest: P,temp: P,slopes: P,report: P,stage_max: P) -> Int:
    var corner=local_corner(x,Int(x[unsafe_offset=40]));var ae=external_acc(x);var invmass=1/x[unsafe_offset=1];var invinertia=1/x[unsafe_offset=2]
    for stage in range(7):
        for j in range(DIM):
            var total=Float64(0)
            for k in range(stage):total+=dp_a(stage,k)*slopes[unsafe_offset=k*DIM+j]
            temp[unsafe_offset=j]=y[unsafe_offset=j]+h*total;stage_max[unsafe_offset=j]=max(stage_max[unsafe_offset=j],abs(temp[unsafe_offset=j]))
        var code=invariant_rhs(x,temp,slopes+stage*DIM,corner,ae,invmass,invinertia);report[unsafe_offset=3]+=1
        if code!=0:return code
    for j in range(DIM):
        var total=Float64(0)
        for k in range(7):total+=dp_b(k)*slopes[unsafe_offset=k*DIM+j]
        dest[unsafe_offset=j]=y[unsafe_offset=j]+h*total
    return 0
