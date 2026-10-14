"""Separate frozen flat-face current-group trial; no advance/integration."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from mojo_game import Vec3,Quaternion
from .core import BodyState,component,finite
from .response_kernels import inv_inertia,kinetic,body_profile
from .friction_kernels import disk_min,tangent_axes
from .temporal_patch_floor_kernels import corner,certified_face,point_order

comptime MARGIN=256*2.220446049250313e-16

def frozen_floor_friction(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    # Canaries0/63 untouched; state and impulses publish only after all gates.
    for i in range(1,63):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=35 else 0.0
    output[unsafe_offset=36]=0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    var half=Vec3(inputs[unsafe_offset=37],inputs[unsafe_offset=38],inputs[unsafe_offset=39]);var mu=inputs[unsafe_offset=40];var beta=inputs[unsafe_offset=41];var c=inputs[unsafe_offset=42];var s=inputs[unsafe_offset=43];var order=Int(inputs[unsafe_offset=44]);var q=b.orientation
    if not body_profile(b) or b.mass<=0 or not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not isfinite(mu) or mu<0 or mu>2 or not isfinite(beta) or beta<0 or not isfinite(c) or not isfinite(s) or abs(c*c+s*s-1)>1e-12 or order<0 or order>=24:output[unsafe_offset=36]=400;return
    if component(b.torque)!=0:output[unsafe_offset=36]=401;return
    if abs(q.x)>5e-11 or abs(q.y)>5e-11 or abs(q.z)>5e-11 or abs(q.w-1)>1e-10 or not certified_face(b,half,0):output[unsafe_offset=36]=402;return
    var permutation=point_order(order);var r=Array[Vec3,4](fill=Vec3(0,0,0));var old=Array[Vec3,4](fill=Vec3(0,0,0));var old_J=Vec3(0,0,0);var old_tau=Vec3(0,0,0)
    for i in range(4):
        var k=permutation[i];var p=corner(b,half,k);p.y*=.5;r[k]=p-b.position;old[k]=Vec3(inputs[unsafe_offset=25+k*3],inputs[unsafe_offset=24+k*3],inputs[unsafe_offset=26+k*3])
        if not finite(old[k]) or old[k].y<0:output[unsafe_offset=36]=400;return
        old_J=old_J+old[k];old_tau=old_tau+r[k].cross(old[k])
    var free=b;free.linear=b.linear-old_J*(1/b.mass);free.angular=b.angular-inv_inertia(b,old_tau)
    output[unsafe_offset=40]=free.linear.x;output[unsafe_offset=41]=free.linear.y;output[unsafe_offset=42]=free.linear.z;output[unsafe_offset=43]=component(free.angular)
    if component(free.angular)>1e-10:output[unsafe_offset=36]=403;return
    var N=b.mass*(beta-free.linear.y)
    if N<0 or beta>max(0.0,-free.linear.y)*(1+MARGIN):output[unsafe_offset=36]=404;return
    var basis=tangent_axes(Vec3(0,1,0),c,s);var t=basis[0];var u=basis[1];var best=disk_min(Vec3(1/b.mass,0,1/b.mass),Vec3(free.linear.dot(t),free.linear.dot(u),0),mu*N);var T=t*best.x+u*best.y
    var h=-r[0].y;var diamond=Float64(0)
    if N>0:diamond=abs(h*T.x/N)/half.x+abs(h*T.z/N)/half.z
    output[unsafe_offset=37]=N;output[unsafe_offset=38]=T.x;output[unsafe_offset=39]=T.z;output[unsafe_offset=51]=diamond
    if not finite(T) or diamond>=1-MARGIN:output[unsafe_offset=36]=405;return
    var next=Array[Vec3,4](fill=Vec3(0,0,0));var next_J=Vec3(0,0,0);var next_tau=Vec3(0,0,0);var delta_J=Vec3(0,0,0);var delta_tau=Vec3(0,0,0)
    for i in range(4):
        var k=permutation[i];var pressure=Float64(0)
        if N>0:pressure=N*.25*(1-r[k].x*h*T.x/(N*half.x*half.x)-r[k].z*h*T.z/(N*half.z*half.z))
        if not isfinite(pressure) or (N>0 and pressure<=0):output[unsafe_offset=36]=405;return
        next[k]=Vec3(T.x*(pressure/N),pressure,T.z*(pressure/N)) if N>0 else Vec3(0,0,0)
        var delta=next[k]-old[k];next_J=next_J+next[k];next_tau=next_tau+r[k].cross(next[k]);delta_J=delta_J+delta;delta_tau=delta_tau+r[k].cross(delta)
        if delta.y<0:output[unsafe_offset=49]+=1
        if delta.x<0 or delta.z<0:output[unsafe_offset=50]+=1
    var trial=b;trial.linear=b.linear+delta_J*(1/b.mass);trial.angular=b.angular+inv_inertia(b,delta_tau)
    var normal_tol=1e-9*(1+abs(free.linear.y));var tangent_tol=1e-9*(1+sqrt(free.linear.x*free.linear.x+free.linear.z*free.linear.z));var nr=Float64(0);var tr=Float64(0);var excess=Float64(0)
    for i in range(4):
        var vn=(trial.linear+trial.angular.cross(r[i])).y-beta;nr=max(nr,abs(vn) if next[i].y>0 else max(0.0,-vn))
        var arm_t=r[i].cross(t);var arm_u=r[i].cross(u);var k=Vec3(1/b.mass+arm_t.dot(inv_inertia(b,arm_t)),arm_t.dot(inv_inertia(b,arm_u)),1/b.mass+arm_u.dot(inv_inertia(b,arm_u)));var x=next[i].dot(t);var y=next[i].dot(u);var v=trial.linear+trial.angular.cross(r[i]);var optimum=disk_min(k,Vec3(v.dot(t)-k.x*x-k.y*y,v.dot(u)-k.y*x-k.z*y,0),mu*next[i].y);var dx=x-optimum.x;var dy=y-optimum.y
        tr=max(tr,sqrt((k.x*dx+k.y*dy)**2+(k.y*dx+k.z*dy)**2));excess=max(excess,sqrt(x*x+y*y)-mu*next[i].y)
        if sqrt(x*x+y*y)>mu*next[i].y+1e-12*(1+mu*next[i].y):output[unsafe_offset=36]=406;return
    output[unsafe_offset=44]=nr;output[unsafe_offset=45]=tr;output[unsafe_offset=46]=max(0.0,excess);output[unsafe_offset=47]=kinetic(trial)-kinetic(b);output[unsafe_offset=48]=kinetic(trial)-kinetic(free);output[unsafe_offset=52]=normal_tol;output[unsafe_offset=53]=tangent_tol;output[unsafe_offset=54]=component(next_tau)
    if nr>normal_tol or tr>tangent_tol:output[unsafe_offset=36]=407;return
    if kinetic(trial)>kinetic(b)+1e-9*(1+kinetic(b)) or kinetic(trial)>kinetic(free)+1e-9*(1+kinetic(free)):output[unsafe_offset=36]=408;return
    if not body_profile(trial) or component(trial.angular)>1e-10:output[unsafe_offset=36]=409;return
    output[unsafe_offset=12]=trial.linear.x;output[unsafe_offset=13]=trial.linear.y;output[unsafe_offset=14]=trial.linear.z;output[unsafe_offset=15]=trial.angular.x;output[unsafe_offset=16]=trial.angular.y;output[unsafe_offset=17]=trial.angular.z
    for i in range(4):output[unsafe_offset=24+i*3]=next[i].y;output[unsafe_offset=25+i*3]=next[i].x;output[unsafe_offset=26+i*3]=next[i].z
