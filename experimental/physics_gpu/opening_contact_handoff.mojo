"""Instantaneous two-feature opening owner; no finite-time continuation."""
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,momentum
from .response_kernels import body_profile,inv_inertia
from .floor_handoff import handoff_bits
from .two_point_inelastic import two_point_inelastic

def opening_contact_reaction(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    for i in range(96):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=44 or i==95 else 0.0
    output[unsafe_offset=39]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    if not body_profile(b) or b.mass<=0:output[unsafe_offset=39]=1200;return
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor=inputs[unsafe_offset=34];var norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(norm-1)>1e-10 or not isfinite(floor) or abs(floor)>1000:output[unsafe_offset=39]=1201;return
    var order=inputs[unsafe_offset=38]
    if b.inertia.x!=b.inertia.y or b.inertia.x!=b.inertia.z or component(b.torque)!=0 or inputs[unsafe_offset=35]!=0 or inputs[unsafe_offset=36]!=0 or (inputs[unsafe_offset=37]!=0 and inputs[unsafe_offset=37]!=1) or not isfinite(order) or order<0 or order>15 or order!=Float64(Int(order)):output[unsafe_offset=39]=1202;return

    var f0=inputs[unsafe_offset=40];var f1=inputs[unsafe_offset=41]
    if not isfinite(f0) or not isfinite(f1) or f0<0 or f0>7 or f1<0 or f1>7 or f0!=Float64(Int(f0)) or f1!=Float64(Int(f1)) or f0==f1:output[unsafe_offset=39]=1801;return
    var i0=Int(f0);var i1=Int(f1);var r0=Vec3(0,0,0);var r1=Vec3(0,0,0);var touching=0
    for visit in range(8):
        var i=(visit+Int(order)%8)%8 if order<8 else (7-visit+Int(order)%8)%8
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z);var arm=b.orientation.rotate(center+shape.rotate(corner));var gap=b.position.y+arm.y-floor;output[unsafe_offset=81+i]=gap
        if not isfinite(gap) or gap < -1e-9:output[unsafe_offset=39]=1802;return
        if gap<=1e-9:touching+=1
        if (i==i0 or i==i1) and abs(gap)>1e-9:output[unsafe_offset=39]=1802;return
        if i==i0:r0=arm
        if i==i1:r1=arm
    if touching!=2:output[unsafe_offset=39]=1802;return
    var u0=(b.linear+b.angular.cross(r0)).y;var u1=(b.linear+b.angular.cross(r1)).y
    output[unsafe_offset=79]=u0;output[unsafe_offset=80]=u1
    if min(u0,u1)< -1e-9:output[unsafe_offset=39]=1803;return
    if max(u0,u1)<=1e-9:output[unsafe_offset=39]=1807;return
    var both=u0>1e-9 and u1>1e-9
    var selected=i0 if u0<=1e-9 else i1
    var r=r0 if selected==i0 else r1;var released=r1 if selected==i0 else r0
    if both:r=r0;released=r1
    var vn=(b.linear+b.angular.cross(r)).y
    output[unsafe_offset=90]= -1 if both else Float64(selected)
    var gravity=Vec3(inputs[unsafe_offset=42],inputs[unsafe_offset=43],inputs[unsafe_offset=44])
    if not finite(gravity) or component(gravity)>1000 or component(b.force)>1000*b.mass:output[unsafe_offset=39]=1206;return
    var n=Vec3(0,1,0);var t=r.cross(n);var K=1/b.mass+t.dot(inv_inertia(b,t))
    var t0=r0.cross(n);var t1=r1.cross(n);var A=1/b.mass+t0.dot(inv_inertia(b,t0));var B=1/b.mass+t0.dot(inv_inertia(b,t1));var C=1/b.mass+t1.dot(inv_inertia(b,t1));var determinant=(A*C-B*B)/(A*C)
    output[unsafe_offset=53]=determinant
    if not isfinite(determinant) or determinant<=1e-4:output[unsafe_offset=39]=1804;return
    if not isfinite(K) or K<=0:output[unsafe_offset=39]=1804;return
    var external=b.force+gravity*b.mass;var gyro=b.angular.cross(momentum(b.orientation,b.inertia,b.angular));var free_a=external*(1/b.mass);var free_alpha=inv_inertia(b,b.torque-gyro);var centr=b.angular.cross(b.angular.cross(r));var q=(free_a+free_alpha.cross(r)+centr).y;var tol=1e-9*(1+abs(q));var N=Float64(0);var phase=3
    if not both:
        if q < -tol:N=-q/K;phase=1
        elif q>tol:phase=2
        else:output[unsafe_offset=39]=1807;return
    output[unsafe_offset=89]=N
    if not isfinite(N) or N<0:output[unsafe_offset=39]=1804;return
    var support=n*N;var torque=t*N;var a=(external+support)*(1/b.mass);var alpha=inv_inertia(b,b.torque+torque-gyro)
    output[unsafe_offset=91]=component(a);output[unsafe_offset=92]=component(alpha)
    if not finite(a) or not finite(alpha) or component(a)>1000 or component(alpha)>1000:output[unsafe_offset=39]=1805;return
    var post=(a+alpha.cross(r)+centr).y;var residual=Float64(0) if both else abs(post) if N>0 else max(0.0,-post)
    var force_error=(a*b.mass-external-support).length();var Ldot=momentum(b.orientation,b.inertia,alpha)+gyro;var moment_error=(Ldot-b.torque-torque).length();var origin_error=(Ldot+b.position.cross(a*b.mass)-b.position.cross(external)-b.torque-(b.position+r).cross(support)).length();var contact_power=N*vn;var external_power=external.dot(b.linear)+b.torque.dot(b.angular);var rate=(a*b.mass).dot(b.linear)+momentum(b.orientation,b.inertia,alpha).dot(b.angular);var power_error=abs(rate-external_power-contact_power)
    if residual>tol or force_error>1e-10*(1+external.length()+support.length()) or moment_error>1e-10*(1+b.torque.length()+torque.length()) or origin_error>1e-10*(1+b.position.cross(external).length()+(b.position+r).cross(support).length()) or abs(contact_power)>1e-9*(1+N) or power_error>1e-9*(1+abs(external_power)+abs(contact_power)):output[unsafe_offset=39]=1806;return
    output[unsafe_offset=93]=Float64(phase);output[unsafe_offset=51]=(a+alpha.cross(released)+b.angular.cross(b.angular.cross(released))).y
    output[unsafe_offset=45]=1 if N>0 else 0;output[unsafe_offset=46]=N;output[unsafe_offset=48]=q;output[unsafe_offset=50]=post;output[unsafe_offset=52]=K;output[unsafe_offset=56]=tol;output[unsafe_offset=57]=residual;output[unsafe_offset=58]=force_error;output[unsafe_offset=59]=moment_error;output[unsafe_offset=60]=origin_error;output[unsafe_offset=61]=contact_power;output[unsafe_offset=62]=power_error;output[unsafe_offset=63]=external_power;output[unsafe_offset=64]=rate;output[unsafe_offset=65]=centr.y
    for k in range(3):
        output[unsafe_offset=67+k]=a.x if k==0 else a.y if k==1 else a.z;output[unsafe_offset=70+k]=alpha.x if k==0 else alpha.y if k==1 else alpha.z;output[unsafe_offset=73+k]=support.x if k==0 else support.y if k==1 else support.z;output[unsafe_offset=76+k]=torque.x if k==0 else torque.y if k==1 else torque.z

def opening_contact_handoff(inputs: Pointer[Float64,MutAnyOrigin],previous: Pointer[Float64,MutAnyOrigin],request: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin],scratch: Pointer[Float64,MutAnyOrigin],status: Pointer[Float64,MutAnyOrigin]):
    for i in range(128):output[unsafe_offset=i]=previous[unsafe_offset=i]
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var epoch=previous[unsafe_offset=96];var revision=previous[unsafe_offset=97]
    if not isfinite(epoch) or epoch<0 or epoch>=1000000 or epoch!=Float64(Int(epoch)) or not isfinite(revision) or revision<0 or revision>=1000000 or revision!=Float64(Int(revision)) or request[unsafe_offset=0]!=epoch:status[unsafe_offset=0]=1700;return
    for i in range(6):
        var key=request[unsafe_offset=2+i]
        if not isfinite(key) or key<1 or key>1e9 or key!=Float64(Int(key)) or (epoch!=0 and key!=previous[unsafe_offset=106+i]):status[unsafe_offset=0]=1702;return
    var changed=False
    for i in range(1,45):
        if i!=39 and handoff_bits(inputs[unsafe_offset=i])!=handoff_bits(previous[unsafe_offset=i]):changed=True
    var required=revision+1 if changed or epoch==0 else revision
    if request[unsafe_offset=1]!=required:status[unsafe_offset=0]=1701;return
    for i in range(96):scratch[unsafe_offset=i]=inputs[unsafe_offset=i]
    opening_contact_reaction(scratch,scratch+192)
    var code=scratch[unsafe_offset=231];var impacted=False
    if code==1803:
        if max(scratch[unsafe_offset=271],scratch[unsafe_offset=272])>1e-9:status[unsafe_offset=0]=1704;return
        two_point_inelastic(scratch,scratch+96)
        if scratch[unsafe_offset=135]!=0:status[unsafe_offset=0]=1705;status[unsafe_offset=1]=scratch[unsafe_offset=135];return
        for i in range(12,18):scratch[unsafe_offset=i]=scratch[unsafe_offset=96+i]
        impacted=True
        opening_contact_reaction(scratch,scratch+192)
        code=scratch[unsafe_offset=231]
    if code!=0:status[unsafe_offset=0]=1706;status[unsafe_offset=1]=code;return
    for i in range(96):output[unsafe_offset=i]=scratch[unsafe_offset=192+i]
    output[unsafe_offset=96]=epoch+1;output[unsafe_offset=97]=required;output[unsafe_offset=98]=20+scratch[unsafe_offset=285]
    output[unsafe_offset=102]=0;output[unsafe_offset=103]=0;output[unsafe_offset=104]=0
    if impacted:
        output[unsafe_offset=99]=previous[unsafe_offset=99]+1
        output[unsafe_offset=100]=scratch[unsafe_offset=140];output[unsafe_offset=101]=scratch[unsafe_offset=141]
        output[unsafe_offset=102]=scratch[unsafe_offset=140];output[unsafe_offset=103]=scratch[unsafe_offset=141];output[unsafe_offset=104]=scratch[unsafe_offset=154]
    output[unsafe_offset=105]=2
    for i in range(6):output[unsafe_offset=106+i]=request[unsafe_offset=2+i]
    var active=output[unsafe_offset=90]
    output[unsafe_offset=112]= -1 if active<0 else inputs[unsafe_offset=41] if active==inputs[unsafe_offset=40] else inputs[unsafe_offset=40]
    output[unsafe_offset=113]=active if output[unsafe_offset=98]==21 else -1
    output[unsafe_offset=114]=output[unsafe_offset=79];output[unsafe_offset=115]=output[unsafe_offset=80]
