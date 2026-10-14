"""Outward scalar operations for local geometry inequalities, not an ODE proof."""
from std.memory import Pointer
from std.math import sqrt,isfinite

@fieldwise_init
struct Bound(ImplicitlyCopyable,Movable):
    var lo: Float64
    var hi: Float64

def next_up(x: Float64) -> Float64:
    if x==0:return 4.9406564584124654e-324
    var v=x;var p=Pointer[UInt64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=v)))
    p[]=p[]+1 if x>0 else p[]-1
    return v

def next_down(x: Float64) -> Float64:
    return -next_up(-x)
def point(x: Float64) -> Bound:return Bound(x,x)
def widen(x: Float64,e: Float64) -> Bound:return Bound(next_down(x-e),next_up(x+e))
def plus(a: Bound,b: Bound) -> Bound:return Bound(next_down(a.lo+b.lo),next_up(a.hi+b.hi))
def minus(a: Bound,b: Bound) -> Bound:return Bound(next_down(a.lo-b.hi),next_up(a.hi-b.lo))
def times(a: Bound,b: Bound) -> Bound:
    var x=a.lo*b.lo;var y=a.lo*b.hi;var z=a.hi*b.lo;var w=a.hi*b.hi
    return Bound(next_down(min(min(x,y),min(z,w))),next_up(max(max(x,y),max(z,w))))
def divide(a: Bound,b: Bound) -> Bound:
    return times(a,Bound(next_down(1/b.hi),next_up(1/b.lo)))
def square(a: Bound) -> Bound:
    var low=min(a.lo*a.lo,a.hi*a.hi) if a.lo*a.hi>0 else Float64(0)
    return Bound(max(0.0,next_down(low)),next_up(max(a.lo*a.lo,a.hi*a.hi)))
def root(a: Bound) -> Bound:return Bound(max(0.0,next_down(sqrt(max(0.0,a.lo)))),next_up(sqrt(a.hi)))
def magnitude(a: Bound) -> Float64:return max(abs(a.lo),abs(a.hi))

@fieldwise_init
struct Bound3(ImplicitlyCopyable,Movable):
    var x: Bound
    var y: Bound
    var z: Bound

def fixed3(x: Float64,y: Float64,z: Float64) -> Bound3:return Bound3(point(x),point(y),point(z))
def add3(a: Bound3,b: Bound3) -> Bound3:return Bound3(plus(a.x,b.x),plus(a.y,b.y),plus(a.z,b.z))
def scale3(a: Bound3,b: Bound) -> Bound3:return Bound3(times(a.x,b),times(a.y,b),times(a.z,b))
def cross3(a: Bound3,b: Bound3) -> Bound3:return Bound3(minus(times(a.y,b.z),times(a.z,b.y)),minus(times(a.z,b.x),times(a.x,b.z)),minus(times(a.x,b.y),times(a.y,b.x)))
def norm3(a: Bound3) -> Bound:return root(plus(plus(square(a.x),square(a.y)),square(a.z)))
def rotate3(qx: Bound,qy: Bound,qz: Bound,qw: Bound,v: Bound3) -> Bound3:
    var norm=root(plus(plus(square(qx),square(qy)),plus(square(qz),square(qw))))
    var q=Bound3(divide(qx,norm),divide(qy,norm),divide(qz,norm));var w=divide(qw,norm);var t=scale3(cross3(q,v),point(2))
    return add3(v,add3(scale3(t,w),cross3(q,t)))
