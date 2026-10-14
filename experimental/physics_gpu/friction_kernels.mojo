"""G04b cold, circular-cone maximum-dissipation tangent blocks on GPU."""
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game import Vec3
from .kernels import load,store,CAPACITY
from .core import BodyState,finite
from .response_kernels import inv_mass,inv_inertia,kinetic,body_profile,normal,point,normal_speed,apply_normal

def tangent_axes(n: Vec3,c: Float64,s: Float64) -> Tuple[Vec3,Vec3]:
    var axis=Vec3(1,0,0)
    if abs(n.y)<abs(n.x) and abs(n.y)<=abs(n.z):axis=Vec3(0,1,0)
    elif abs(n.z)<abs(n.x) and abs(n.z)<abs(n.y):axis=Vec3(0,0,1)
    var t=n.cross(axis);t=t*(1/t.length());var v=n.cross(t)
    return t*c+v*s,v*c-t*s
def point_velocity(a: BodyState,b: BodyState,p: Vec3) -> Vec3:
    return b.linear+b.angular.cross(p-b.position)-a.linear-a.angular.cross(p-a.position)
def tangent_metric(a: BodyState,b: BodyState,p: Vec3,t: Vec3,u: Vec3) -> Vec3:
    var at=(p-a.position).cross(t);var au=(p-a.position).cross(u)
    var bt=(p-b.position).cross(t);var bu=(p-b.position).cross(u)
    var mass=inv_mass(a)+inv_mass(b)
    return Vec3(mass+at.dot(inv_inertia(a,at))+bt.dot(inv_inertia(b,bt)),at.dot(inv_inertia(a,au))+bt.dot(inv_inertia(b,bu)),mass+au.dot(inv_inertia(a,au))+bu.dot(inv_inertia(b,bu)))
def shifted_min(k: Vec3,u: Vec3,eta: Float64) -> Vec3:
    var a=k.x+eta;var d=k.z+eta;var determinant=a*d-k.y*k.y
    return Vec3((-d*u.x+k.y*u.y)/determinant,(k.y*u.x-a*u.y)/determinant,eta)
def disk_min(k: Vec3,u: Vec3,radius: Float64) -> Vec3:
    if radius==0:return Vec3(0,0,0)
    var unconstrained=shifted_min(k,u,0)
    if sqrt(unconstrained.x*unconstrained.x+unconstrained.y*unconstrained.y)<=radius:return unconstrained
    # eta >= ||u||/radius is a feasible upper bracket for SPD K.
    var low=Float64(0);var high=sqrt(u.x*u.x+u.y*u.y)/radius
    for _ in range(64):
        var middle=low*.5+high*.5;var trial=shifted_min(k,u,middle)
        if sqrt(trial.x*trial.x+trial.y*trial.y)>radius:low=middle
        else:high=middle
    return shifted_min(k,u,high)
def apply_tangent(mut a: BodyState,mut b: BodyState,p: Vec3,j: Vec3):
    if a.mass>0:
        a.linear=a.linear-j*inv_mass(a);a.angular=a.angular-inv_inertia(a,(p-a.position).cross(j))
    if b.mass>0:
        b.linear=b.linear+j*inv_mass(b);b.angular=b.angular+inv_inertia(b,(p-b.position).cross(j))

def prepare_friction(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],count: Int32,capacity: Int32,mu: Float64,c: Float64,s: Float64):
    for i in range(5):stats[unsafe_offset=i]=0
    if summary[unsafe_offset=0]!=0:return
    if not isfinite(mu) or mu<0 or mu>2 or not isfinite(c) or not isfinite(s) or abs(c*c+s*s-1)>1e-12:summary[unsafe_offset=0]=62;return
    for i in range(Int(capacity)*2+2):tangent[unsafe_offset=i]=0
    stats[unsafe_offset=4]=1e-9
    for i in range(Int(count)):
        var h=1+i*11;var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]))
        var n=normal(geometry,i);var v=point_velocity(a,b,point(geometry,i));var vt=v-n*v.dot(n)
        stats[unsafe_offset=4]=max(stats[unsafe_offset=4],1e-9*(1+vt.length()))

def solve_friction(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],targets: Pointer[Float64,MutAnyOrigin],effective: Pointer[Float64,MutAnyOrigin],touched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],normal_stats: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],count: Int32,iterations: Int32,mu: Float64,c: Float64,s: Float64):
    if summary[unsafe_offset=0]!=0:return
    var converged=Int(count)==0;var normal_residual=Float64(0);var friction_residual=Float64(0)
    for sweep in range(Int(iterations)):
        if converged:break
        for i in range(Int(count)):
            if effective[unsafe_offset=i+1]==0:continue
            var h=1+i*11;var ia=Int(headers[unsafe_offset=h+3]);var ib=Int(headers[unsafe_offset=h+8]);var a=load(candidate,ia);var b=load(candidate,ib)
            var n=normal(geometry,i);var p=point(geometry,i);var basis=tangent_axes(n,c,s);var t=basis[0];var v=basis[1]
            var old_normal=impulses[unsafe_offset=i+1];var next_normal=max(0.0,old_normal+(targets[unsafe_offset=i+1]-normal_speed(a,b,p,n))/effective[unsafe_offset=i+1])
            if not isfinite(next_normal) or next_normal>1e4:summary[unsafe_offset=0]=61;return
            apply_normal(a,b,p,n,next_normal-old_normal);impulses[unsafe_offset=i+1]=next_normal
            var k=tangent_metric(a,b,p,t,v)
            if not finite(k) or k.x<=0 or k.z<=0 or k.x*k.z-k.y*k.y<=0:summary[unsafe_offset=0]=64;return
            var old_x=tangent[unsafe_offset=1+i*2];var old_y=tangent[unsafe_offset=2+i*2];var velocity=point_velocity(a,b,p)
            var u=Vec3(velocity.dot(t)-k.x*old_x-k.y*old_y,velocity.dot(v)-k.y*old_x-k.z*old_y,0)
            var next=disk_min(k,u,mu*next_normal)
            if not finite(next):summary[unsafe_offset=0]=64;return
            apply_tangent(a,b,p,t*(next.x-old_x)+v*(next.y-old_y))
            if not body_profile(a) or not body_profile(b):summary[unsafe_offset=0]=52;return
            tangent[unsafe_offset=1+i*2]=next.x;tangent[unsafe_offset=2+i*2]=next.y;store(candidate,ia,a);store(candidate,ib,b)
        normal_residual=0;friction_residual=0;stats[unsafe_offset=1]=0;stats[unsafe_offset=2]=0;stats[unsafe_offset=3]=0
        for i in range(Int(count)):
            if effective[unsafe_offset=i+1]==0:continue
            var h=1+i*11;var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]));var n=normal(geometry,i);var p=point(geometry,i)
            var error=normal_speed(a,b,p,n)-targets[unsafe_offset=i+1];var lambda_n=impulses[unsafe_offset=i+1]
            normal_residual=max(normal_residual,abs(error) if lambda_n>0 else max(0.0,-error))
            var basis=tangent_axes(n,c,s);var t=basis[0];var v=basis[1];var k=tangent_metric(a,b,p,t,v);var velocity=point_velocity(a,b,p)
            var old_x=tangent[unsafe_offset=1+i*2];var old_y=tangent[unsafe_offset=2+i*2]
            var u=Vec3(velocity.dot(t)-k.x*old_x-k.y*old_y,velocity.dot(v)-k.y*old_x-k.z*old_y,0);var radius=mu*lambda_n
            var optimum=disk_min(k,u,radius);var dx=old_x-optimum.x;var dy=old_y-optimum.y
            friction_residual=max(friction_residual,sqrt((k.x*dx+k.y*dy)**2+(k.y*dx+k.z*dy)**2))
            var length=sqrt(old_x*old_x+old_y*old_y);var excess=max(0.0,length-radius)
            stats[unsafe_offset=1]=max(stats[unsafe_offset=1],length);stats[unsafe_offset=2]=max(stats[unsafe_offset=2],excess)
            if excess>1e-12*(1+radius):summary[unsafe_offset=0]=64;return
            if radius>0 and optimum.z>0:stats[unsafe_offset=3]+=1
        summary[unsafe_offset=1]=Int32(sweep+1);normal_stats[unsafe_offset=2]=normal_residual;stats[unsafe_offset=0]=friction_residual
        converged=normal_residual<=normal_stats[unsafe_offset=5] and friction_residual<=stats[unsafe_offset=4]
    if not converged:
        summary[unsafe_offset=0]=Int32(55 if normal_residual>normal_stats[unsafe_offset=5] else 63);return
    var energy=Float64(0)
    for i in range(CAPACITY):
        if touched[unsafe_offset=i+1]:energy+=kinetic(load(candidate,i))
    normal_stats[unsafe_offset=1]=energy
    if not isfinite(energy) or energy>normal_stats[unsafe_offset=0]+1e-9*(1+normal_stats[unsafe_offset=0]):summary[unsafe_offset=0]=56
