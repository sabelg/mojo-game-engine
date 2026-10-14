"""Isolated frictionless e=0 two-vertex floor impulse. No time advance."""
from std.collections import Array
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,momentum
from .response_kernels import body_profile,inv_inertia,kinetic

@fieldwise_init
struct NormalPairSolution(ImplicitlyCopyable,Movable):
    var code: Int
    var mask: Int
    var a: Float64
    var b: Float64
    var relative_determinant: Float64

def solve_normal_pair(A: Float64,B: Float64,C: Float64,u: Float64,v: Float64) -> NormalPairSolution:
    var result=NormalPairSolution(1105,0,0,0,0)
    if not isfinite(A) or not isfinite(B) or not isfinite(C) or not isfinite(u) or not isfinite(v) or A<=0 or C<=0:return result
    var determinant=A*C-B*B;var scale=A*C
    if not isfinite(determinant) or not isfinite(scale) or scale<=0:return result
    result.relative_determinant=determinant/scale
    # Reject redundant/ill-conditioned constraints; no diagonal regularization.
    if result.relative_determinant<=1e-4:return result
    result.code=1106
    for mask in range(4):
        var a=Float64(0);var b=Float64(0)
        if mask==1:a=-u/A
        elif mask==2:b=-v/C
        elif mask==3:a=(B*v-C*u)/determinant;b=(B*u-A*v)/determinant
        if not isfinite(a) or not isfinite(b) or a<0 or b<0:continue
        var w0=u+A*a+B*b;var w1=v+B*a+C*b;var tol=1e-9*(1+max(abs(u),abs(v)))
        if (mask%2==0 and w0<0) or (mask//2==0 and w1<0):continue
        if (mask%2==1 and abs(w0)>tol) or (mask//2==1 and abs(w1)>tol):continue
        return NormalPairSolution(0,mask,a,b,result.relative_determinant)
    return result

def two_point_inelastic(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    for i in range(1,95):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=41 else 0.0
    output[unsafe_offset=39]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    if not body_profile(b) or b.mass<=0:output[unsafe_offset=39]=1100;return
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor=inputs[unsafe_offset=34];var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor) or abs(floor)>1000:output[unsafe_offset=39]=1101;return
    var order=inputs[unsafe_offset=38]
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0 or inputs[unsafe_offset=36]!=0 or (inputs[unsafe_offset=37]!=0 and inputs[unsafe_offset=37]!=1) or not isfinite(order) or order<0 or order>15 or order!=Float64(Int(order)):output[unsafe_offset=39]=1102;return
    var f0=inputs[unsafe_offset=40];var f1=inputs[unsafe_offset=41]
    if not isfinite(f0) or not isfinite(f1) or f0<0 or f0>7 or f1<0 or f1>7 or f0!=Float64(Int(f0)) or f1!=Float64(Int(f1)) or f0==f1:output[unsafe_offset=39]=1103;return
    var i0=Int(f0);var i1=Int(f1);var arms=Array[Vec3,8](fill=Vec3(0,0,0));var speeds=Array[Float64,8](fill=0);var touching=0
    for visit in range(8):
        var i=(visit+Int(order)%8)%8 if order<8 else (7-visit+Int(order)%8)%8
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z);arms[i]=b.orientation.rotate(center+shape.rotate(corner));var gap=b.position.y+arms[i].y-floor;speeds[i]=(b.linear+b.angular.cross(arms[i])).y;output[unsafe_offset=71+i]=gap;output[unsafe_offset=85+i]=speeds[i]
        if not isfinite(gap) or gap < -1e-9:output[unsafe_offset=39]=1104;return
        if gap<=1e-9:touching+=1
        if (i==i0 or i==i1) and abs(gap)>1e-9:output[unsafe_offset=39]=1104;return
    if touching!=2:output[unsafe_offset=39]=1104;return
    var r0=arms[i0];var r1=arms[i1];var n=Vec3(0,1,0);var t0=r0.cross(n);var t1=r1.cross(n);var A=1/b.mass+t0.dot(inv_inertia(b,t0));var B=1/b.mass+t0.dot(inv_inertia(b,t1));var C=1/b.mass+t1.dot(inv_inertia(b,t1));var u=speeds[i0];var v=speeds[i1];var solution=solve_normal_pair(A,B,C,u,v)
    output[unsafe_offset=43]=Float64(solution.mask);output[unsafe_offset=44]=solution.a;output[unsafe_offset=45]=solution.b;output[unsafe_offset=46]=u;output[unsafe_offset=47]=v;output[unsafe_offset=50]=A;output[unsafe_offset=51]=B;output[unsafe_offset=52]=C;output[unsafe_offset=53]=solution.relative_determinant
    if solution.code!=0:output[unsafe_offset=39]=Float64(solution.code);return
    var J=n*(solution.a+solution.b);var tau=t0*solution.a+t1*solution.b;var trial=b
    if solution.a>0 or solution.b>0:trial.linear=b.linear+J*(1/b.mass);trial.angular=b.angular+inv_inertia(b,tau)
    var w0=(trial.linear+trial.angular.cross(r0)).y;var w1=(trial.linear+trial.angular.cross(r1)).y;var tolerance=1e-9*(1+max(abs(u),abs(v)));var residual=max(max(0.0,-w0),max(0.0,-w1))
    if solution.a>0:residual=max(residual,abs(w0))
    if solution.b>0:residual=max(residual,abs(w1))
    var before=kinetic(b);var after=kinetic(trial);var loss= -(solution.a*u+solution.b*v+.5*(A*solution.a*solution.a+2*B*solution.a*solution.b+C*solution.b*solution.b));var dp=(trial.linear-b.linear)*b.mass;var dL=momentum(trial.orientation,trial.inertia,trial.angular)-momentum(b.orientation,b.inertia,b.angular);var perr=(dp-J).length();var Lerr=(dL-tau).length();var origin_err=(dL+b.position.cross(dp)-(b.position+r0).cross(n*solution.a)-(b.position+r1).cross(n*solution.b)).length();var Eerr=abs(after-before+loss)
    output[unsafe_offset=48]=w0;output[unsafe_offset=49]=w1;output[unsafe_offset=54]=tolerance;output[unsafe_offset=55]=residual;output[unsafe_offset=56]=before;output[unsafe_offset=57]=after;output[unsafe_offset=58]=loss;output[unsafe_offset=59]=Eerr;output[unsafe_offset=60]=perr;output[unsafe_offset=61]=Lerr;output[unsafe_offset=62]=origin_err;output[unsafe_offset=63]=tau.x;output[unsafe_offset=64]=tau.y;output[unsafe_offset=65]=tau.z;output[unsafe_offset=66]=J.y;output[unsafe_offset=68]=max(abs(solution.a*w0),abs(solution.b*w1));output[unsafe_offset=69]=b.angular.length();output[unsafe_offset=70]=trial.angular.length();output[unsafe_offset=93]=1e-9*(1+before)
    for k in range(3):output[unsafe_offset=79+k]=r0.x if k==0 else r0.y if k==1 else r0.z;output[unsafe_offset=82+k]=r1.x if k==0 else r1.y if k==1 else r1.z
    if not body_profile(trial):output[unsafe_offset=39]=1107;return
    if residual>tolerance or loss < -1e-9*(1+before) or after>before+1e-9*(1+before) or Eerr>1e-9*(1+before) or perr>1e-10*(1+J.length()) or Lerr>1e-10*(1+tau.length()) or origin_err>1e-10*(1+((b.position+r0).cross(n*solution.a)+(b.position+r1).cross(n*solution.b)).length()):output[unsafe_offset=39]=1108;return
    if solution.a>0 or solution.b>0:
        output[unsafe_offset=12]=trial.linear.x;output[unsafe_offset=13]=trial.linear.y;output[unsafe_offset=14]=trial.linear.z;output[unsafe_offset=15]=trial.angular.x;output[unsafe_offset=16]=trial.angular.y;output[unsafe_offset=17]=trial.angular.z
