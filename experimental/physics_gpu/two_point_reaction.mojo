"""Isolated zero-normal-speed reaction/acceleration solve. No time or impulse."""
from std.collections import Array
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,momentum
from .response_kernels import body_profile,inv_inertia
from .two_point_inelastic import solve_normal_pair,NormalPairSolution

def solve_reaction_pair(A: Float64,B: Float64,C: Float64,u: Float64,v: Float64) -> NormalPairSolution:
    var solved=solve_normal_pair(A,B,C,u,v)
    if solved.code!=1106:return solved
    # Same four active sets, evaluated by elimination if the direct arithmetic
    # cannot certify a zero-multiplier boundary. No tolerance/sign clamp.
    var ratio=B/A;var other=v-ratio*u;var a=-u/A
    if isfinite(a) and a>=0 and other>=0:return NormalPairSolution(0,1,a,0,solved.relative_determinant)
    var ratio2=B/C;var other2=u-ratio2*v;var b=-v/C
    if isfinite(b) and b>=0 and other2>=0:return NormalPairSolution(0,2,0,b,solved.relative_determinant)
    var schur=C-B*ratio
    if not isfinite(schur) or schur<=0:return solved
    b=-other/schur;a=-(u+B*b)/A
    if not isfinite(a) or not isfinite(b) or a<0 or b<0:return solved
    return NormalPairSolution(0,3,a,b,solved.relative_determinant)

def two_point_reaction(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    for i in range(1,95):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=44 else 0.0
    output[unsafe_offset=39]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    if not body_profile(b) or b.mass<=0:output[unsafe_offset=39]=1200;return
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor=inputs[unsafe_offset=34];var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor) or abs(floor)>1000:output[unsafe_offset=39]=1201;return
    var order=inputs[unsafe_offset=38]
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0 or inputs[unsafe_offset=36]!=0 or (inputs[unsafe_offset=37]!=0 and inputs[unsafe_offset=37]!=1) or not isfinite(order) or order<0 or order>15 or order!=Float64(Int(order)):output[unsafe_offset=39]=1202;return
    var f0=inputs[unsafe_offset=40];var f1=inputs[unsafe_offset=41]
    if not isfinite(f0) or not isfinite(f1) or f0<0 or f0>7 or f1<0 or f1>7 or f0!=Float64(Int(f0)) or f1!=Float64(Int(f1)) or f0==f1:output[unsafe_offset=39]=1203;return
    var i0=Int(f0);var i1=Int(f1);var arms=Array[Vec3,8](fill=Vec3(0,0,0));var speeds=Array[Float64,8](fill=0);var touching=0
    for visit in range(8):
        var i=(visit+Int(order)%8)%8 if order<8 else (7-visit+Int(order)%8)%8
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z);arms[i]=b.orientation.rotate(center+shape.rotate(corner));var gap=b.position.y+arms[i].y-floor;speeds[i]=(b.linear+b.angular.cross(arms[i])).y;output[unsafe_offset=81+i]=gap
        if not isfinite(gap) or gap < -1e-9:output[unsafe_offset=39]=1204;return
        if gap<=1e-9:touching+=1
        if (i==i0 or i==i1) and abs(gap)>1e-9:output[unsafe_offset=39]=1204;return
    if touching!=2:output[unsafe_offset=39]=1204;return
    var r0=arms[i0];var r1=arms[i1];var n=Vec3(0,1,0);var vn0=speeds[i0];var vn1=speeds[i1];output[unsafe_offset=79]=vn0;output[unsafe_offset=80]=vn1
    # A closing impact and a separating contact are not zero-speed support.
    # No velocity is snapped to zero to gain admission.
    if abs(vn0)>1e-9 or abs(vn1)>1e-9:output[unsafe_offset=39]=1205;return
    var gravity=Vec3(inputs[unsafe_offset=42],inputs[unsafe_offset=43],inputs[unsafe_offset=44])
    if not finite(gravity) or component(gravity)>1000 or component(b.force)>1000*b.mass:output[unsafe_offset=39]=1206;return
    var external=b.force+gravity*b.mass;var free_a=external*(1/b.mass);var L=momentum(b.orientation,b.inertia,b.angular);var gyroscopic=b.angular.cross(L);var free_alpha=inv_inertia(b,b.torque-gyroscopic)
    var centr0=b.angular.cross(b.angular.cross(r0));var centr1=b.angular.cross(b.angular.cross(r1));var free0=(free_a+free_alpha.cross(r0)+centr0).y;var free1=(free_a+free_alpha.cross(r1)+centr1).y
    var t0=r0.cross(n);var t1=r1.cross(n);var A=1/b.mass+t0.dot(inv_inertia(b,t0));var B=1/b.mass+t0.dot(inv_inertia(b,t1));var C=1/b.mass+t1.dot(inv_inertia(b,t1));var solution=solve_reaction_pair(A,B,C,free0,free1)
    output[unsafe_offset=89]=solution.a;output[unsafe_offset=90]=solution.b;output[unsafe_offset=93]=Float64(solution.code)
    if solution.code!=0:output[unsafe_offset=39]=1207 if solution.code==1105 else 1208;return
    var support=n*(solution.a+solution.b);var support_torque=t0*solution.a+t1*solution.b;var acceleration=(external+support)*(1/b.mass);var alpha=inv_inertia(b,b.torque+support_torque-gyroscopic)
    output[unsafe_offset=91]=component(acceleration);output[unsafe_offset=92]=component(alpha)
    # Explicit output acceleration profile, not a clamp or time-step policy.
    if not finite(acceleration) or not finite(alpha) or component(acceleration)>1000 or component(alpha)>1000:output[unsafe_offset=39]=1209;return
    var post0=(acceleration+alpha.cross(r0)+centr0).y;var post1=(acceleration+alpha.cross(r1)+centr1).y;var tol=1e-9*(1+max(abs(free0),abs(free1)));var residual=max(max(0.0,-post0),max(0.0,-post1))
    if solution.a>0:residual=max(residual,abs(post0))
    if solution.b>0:residual=max(residual,abs(post1))
    var force_error=(acceleration*b.mass-external-support).length();var Ldot=momentum(b.orientation,b.inertia,alpha)+gyroscopic;var moment_error=(Ldot-b.torque-support_torque).length();var origin_error=(Ldot+b.position.cross(acceleration*b.mass)-b.position.cross(external)-b.torque-(b.position+r0).cross(n*solution.a)-(b.position+r1).cross(n*solution.b)).length()
    var contact_power=solution.a*vn0+solution.b*vn1;var external_power=external.dot(b.linear)+b.torque.dot(b.angular);var kinetic_rate=(acceleration*b.mass).dot(b.linear)+momentum(b.orientation,b.inertia,alpha).dot(b.angular);var power_error=abs(kinetic_rate-external_power-contact_power)
    if residual>tol or force_error>1e-10*(1+external.length()+support.length()) or moment_error>1e-10*(1+b.torque.length()+support_torque.length()) or origin_error>1e-10*(1+b.position.cross(external).length()+((b.position+r0).cross(n*solution.a)+(b.position+r1).cross(n*solution.b)).length()) or abs(contact_power)>1e-9*(1+solution.a+solution.b) or power_error>1e-9*(1+abs(external_power)+abs(contact_power)):output[unsafe_offset=39]=1210;return
    # Publish only acceleration/reaction results. Body, forces and episode untouched.
    output[unsafe_offset=45]=Float64(solution.mask);output[unsafe_offset=46]=solution.a;output[unsafe_offset=47]=solution.b;output[unsafe_offset=48]=free0;output[unsafe_offset=49]=free1;output[unsafe_offset=50]=post0;output[unsafe_offset=51]=post1;output[unsafe_offset=52]=A;output[unsafe_offset=53]=B;output[unsafe_offset=54]=C;output[unsafe_offset=55]=solution.relative_determinant;output[unsafe_offset=56]=tol;output[unsafe_offset=57]=residual;output[unsafe_offset=58]=force_error;output[unsafe_offset=59]=moment_error;output[unsafe_offset=60]=origin_error;output[unsafe_offset=61]=contact_power;output[unsafe_offset=62]=power_error;output[unsafe_offset=63]=external_power;output[unsafe_offset=64]=kinetic_rate;output[unsafe_offset=65]=centr0.y;output[unsafe_offset=66]=centr1.y
    for k in range(3):
        output[unsafe_offset=67+k]=acceleration.x if k==0 else acceleration.y if k==1 else acceleration.z;output[unsafe_offset=70+k]=alpha.x if k==0 else alpha.y if k==1 else alpha.z;output[unsafe_offset=73+k]=support.x if k==0 else support.y if k==1 else support.z;output[unsafe_offset=76+k]=support_torque.x if k==0 else support_torque.y if k==1 else support_torque.z
