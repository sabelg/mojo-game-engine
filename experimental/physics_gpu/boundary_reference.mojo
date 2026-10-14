"""Archived pre-G04a boundary reference for exact rotated-tangency regression."""
from std.collections import Array
from std.math import sqrt
from mojo_game import Vec3,Quaternion
from .contact_oracle import OracleSphere,oracle_center
from .box_oracle import OracleBox,box_center,apply

def legacy_matrix(q: Quaternion) -> Array[Float64,9]:
    var scale=max(max(abs(q.x),abs(q.y)),max(abs(q.z),abs(q.w)))
    var x=q.x/scale;var y=q.y/scale;var z=q.z/scale;var w=q.w/scale
    var length=sqrt(x*x+y*y+z*z+w*w);x/=length;y/=length;z/=length;w/=length
    var result=Array[Float64,9](fill=0)
    result[0]=1-2*(y*y+z*z);result[1]=2*(x*y-z*w);result[2]=2*(x*z+y*w)
    result[3]=2*(x*y+z*w);result[4]=1-2*(x*x+z*z);result[5]=2*(y*z-x*w)
    result[6]=2*(x*z-y*w);result[7]=2*(y*z+x*w);result[8]=1-2*(x*x+y*y)
    return result^

def legacy_axes(b: OracleBox) -> Array[Vec3,3]:
    var outer=legacy_matrix(b.body.orientation);var inner=legacy_matrix(b.orientation)
    var result=Array[Vec3,3](fill=Vec3(0,0,0))
    result[0]=apply(outer,apply(inner,Vec3(1,0,0)));result[1]=apply(outer,apply(inner,Vec3(0,1,0)));result[2]=apply(outer,apply(inner,Vec3(0,0,1)))
    return result^

def legacy_separation(s: OracleSphere,b: OracleBox) -> Float64:
    var center=oracle_center(s);var origin=box_center(b);var axes=legacy_axes(b);var d=center-origin
    var u=Array[Float64,3](fill=0);u[0]=d.dot(axes[0]);u[1]=d.dot(axes[1]);u[2]=d.dot(axes[2])
    var half=Array[Float64,3](fill=0);half[0]=b.half_extents.x;half[1]=b.half_extents.y;half[2]=b.half_extents.z
    var best=Float64(1e30)
    for face in range(6):
        var axis=face//2;var sign=Float64(1 if face%2==0 else -1);var score=Float64(0)
        for j in range(3):
            var coordinate=sign*half[j] if j==axis else max(-half[j],min(half[j],u[j]))
            var difference=coordinate-u[j];score+=difference*difference
        best=min(best,score)
    return sqrt(best)-s.radius
