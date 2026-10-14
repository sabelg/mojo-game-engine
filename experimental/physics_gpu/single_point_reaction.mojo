"""Isolated unique-vertex normal reaction; instantaneous force, no impulse."""
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,momentum
from .response_kernels import body_profile,inv_inertia

def single_point_reaction(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    for i in range(96):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=44 or i==95 else 0.0
    output[unsafe_offset=39]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    if not body_profile(b) or b.mass<=0:output[unsafe_offset=39]=1200;return
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor=inputs[unsafe_offset=34];var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor) or abs(floor)>1000:output[unsafe_offset=39]=1201;return
    var order=inputs[unsafe_offset=38]
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0 or inputs[unsafe_offset=36]!=0 or (inputs[unsafe_offset=37]!=0 and inputs[unsafe_offset=37]!=1) or not isfinite(order) or order<0 or order>15 or order!=Float64(Int(order)):output[unsafe_offset=39]=1202;return

    var feature=inputs[unsafe_offset=40]
    if not isfinite(feature) or feature<0 or feature>7 or feature!=Float64(Int(feature)) or inputs[unsafe_offset=41]!=-1:output[unsafe_offset=39]=1401;return
    var selected=Int(feature);var r=Vec3(0,0,0);var touching=0
    for visit in range(8):
        var i=(visit+Int(order)%8)%8 if order<8 else (7-visit+Int(order)%8)%8
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z);var arm=b.orientation.rotate(center+shape.rotate(corner));var gap=b.position.y+arm.y-floor;output[unsafe_offset=81+i]=gap
        if not isfinite(gap) or gap < -1e-9:output[unsafe_offset=39]=1402;return
        if gap<=1e-9:touching+=1
        if i==selected:
            if abs(gap)>1e-9:output[unsafe_offset=39]=1402;return
            r=arm
    if touching!=1:output[unsafe_offset=39]=1402;return
    var vn=(b.linear+b.angular.cross(r)).y;output[unsafe_offset=79]=vn
    if abs(vn)>1e-9:output[unsafe_offset=39]=1403;return
    var gravity=Vec3(inputs[unsafe_offset=42],inputs[unsafe_offset=43],inputs[unsafe_offset=44])
    if not finite(gravity) or component(gravity)>1000 or component(b.force)>1000*b.mass:output[unsafe_offset=39]=1206;return
    var n=Vec3(0,1,0);var t=r.cross(n);var K=1/b.mass+t.dot(inv_inertia(b,t))
    if not isfinite(K) or K<=0:output[unsafe_offset=39]=1404;return
    var external=b.force+gravity*b.mass;var gyro=b.angular.cross(momentum(b.orientation,b.inertia,b.angular));var free_a=external*(1/b.mass);var free_alpha=inv_inertia(b,b.torque-gyro);var centr=b.angular.cross(b.angular.cross(r));var q=(free_a+free_alpha.cross(r)+centr).y;var N=-q/K if q<0 else Float64(0)
    output[unsafe_offset=89]=N
    if not isfinite(N) or N<0:output[unsafe_offset=39]=1404;return
    var support=n*N;var torque=t*N;var a=(external+support)*(1/b.mass);var alpha=inv_inertia(b,b.torque+torque-gyro)
    output[unsafe_offset=91]=component(a);output[unsafe_offset=92]=component(alpha)
    if not finite(a) or not finite(alpha) or component(a)>1000 or component(alpha)>1000:output[unsafe_offset=39]=1405;return
    var post=(a+alpha.cross(r)+centr).y;var tol=1e-9*(1+abs(q));var residual=abs(post) if N>0 else max(0.0,-post)
    var force_error=(a*b.mass-external-support).length();var Ldot=momentum(b.orientation,b.inertia,alpha)+gyro;var moment_error=(Ldot-b.torque-torque).length();var origin_error=(Ldot+b.position.cross(a*b.mass)-b.position.cross(external)-b.torque-(b.position+r).cross(support)).length();var contact_power=N*vn;var external_power=external.dot(b.linear)+b.torque.dot(b.angular);var rate=(a*b.mass).dot(b.linear)+momentum(b.orientation,b.inertia,alpha).dot(b.angular);var power_error=abs(rate-external_power-contact_power)
    if residual>tol or force_error>1e-10*(1+external.length()+support.length()) or moment_error>1e-10*(1+b.torque.length()+torque.length()) or origin_error>1e-10*(1+b.position.cross(external).length()+(b.position+r).cross(support).length()) or abs(contact_power)>1e-9*(1+N) or power_error>1e-9*(1+abs(external_power)+abs(contact_power)):output[unsafe_offset=39]=1406;return
    output[unsafe_offset=45]=1 if N>0 else 0;output[unsafe_offset=46]=N;output[unsafe_offset=48]=q;output[unsafe_offset=50]=post;output[unsafe_offset=52]=K;output[unsafe_offset=56]=tol;output[unsafe_offset=57]=residual;output[unsafe_offset=58]=force_error;output[unsafe_offset=59]=moment_error;output[unsafe_offset=60]=origin_error;output[unsafe_offset=61]=contact_power;output[unsafe_offset=62]=power_error;output[unsafe_offset=63]=external_power;output[unsafe_offset=64]=rate;output[unsafe_offset=65]=centr.y
    for k in range(3):
        output[unsafe_offset=67+k]=a.x if k==0 else a.y if k==1 else a.z;output[unsafe_offset=70+k]=alpha.x if k==0 else alpha.y if k==1 else alpha.z;output[unsafe_offset=73+k]=support.x if k==0 else support.y if k==1 else support.z;output[unsafe_offset=76+k]=torque.x if k==0 else torque.y if k==1 else torque.z
