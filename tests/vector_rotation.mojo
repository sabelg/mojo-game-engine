"""Independent standard Rodrigues/vector identities, no HEPJo code copied.

HEPJo revision 99394a257555eea421344a00aa31836ad92d0e32 motivated the coverage audit.
The oracle uses scalar math, not production Vec3 dot/cross/unit or quaternion math.
"""
from std.math import sin,cos,sqrt
from std.testing import assert_true,assert_equal
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion

def scalar_dot(a: Vec3,b: Vec3) -> Float64:
    return a.x*b.x+a.y*b.y+a.z*b.z
def normalized_axis(a: Vec3) -> Vec3:
    var length=sqrt(a.x*a.x+a.y*a.y+a.z*a.z)
    return Vec3(a.x/length,a.y/length,a.z/length)
def rodrigues(a: Vec3,v: Vec3,angle: Float64) -> Vec3:
    var n=normalized_axis(a);var c=cos(angle);var s=sin(angle);var projection=scalar_dot(n,v)*(1-c)
    return Vec3(c*v.x+s*(n.y*v.z-n.z*v.y)+n.x*projection,
                c*v.y+s*(n.z*v.x-n.x*v.z)+n.y*projection,
                c*v.z+s*(n.x*v.y-n.y*v.x)+n.z*projection)
def near(a: Float64,b: Float64) raises:
    assert_true(abs(a-b)<=1e-11*(1+abs(b)))
def vector(a: Vec3,b: Vec3) raises:
    near(a.x,b.x);near(a.y,b.y);near(a.z,b.z)
def rotation_identities() raises:
    var count=Int(0)
    for raw_axis in [Vec3(2,-3,5),Vec3(-7,4,2),Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,1),Vec3(1,1,1)]:
        var axis=normalized_axis(raw_axis)
        for angle in [Float64(0),Float64(1.5707963267948966),Float64(3.141592653589793),Float64(-.37),Float64(.61)]:
            var q=Quaternion.axis_angle(axis,angle)
            near(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w,Float64(1))
            for v in [Vec3(0,0,0),Vec3(.37,-2,4),Vec3(-5,.7,2.3)]:
                var actual=q.rotate(v);vector(actual,rodrigues(axis,v,angle));near(scalar_dot(actual,actual),scalar_dot(v,v))
                vector(Quaternion.axis_angle(axis,-angle).rotate(actual),v)
                near(scalar_dot(axis,actual),scalar_dot(axis,v))
                for scale in [Float64(.01),Float64(3),Float64(100)]:vector(Quaternion.axis_angle(axis*scale,angle).rotate(v),actual)
                for scale in [Float64(.125),Float64(-3),Float64(11)]:vector(Quaternion(q.x*scale,q.y*scale,q.z*scale,q.w*scale).rotate(v),actual)
                count+=1
    var v=Vec3(.37,-2,4);var quarter=Float64(1.5707963267948966);var half=Float64(3.141592653589793)
    vector(Quaternion.axis_angle(Vec3(1,0,0),quarter).rotate(v),Vec3(v.x,-v.z,v.y))
    vector(Quaternion.axis_angle(Vec3(0,1,0),quarter).rotate(v),Vec3(v.z,v.y,-v.x))
    vector(Quaternion.axis_angle(Vec3(0,0,1),quarter).rotate(v),Vec3(-v.y,v.x,v.z))
    vector(Quaternion.axis_angle(Vec3(1,0,0),half).rotate(v),Vec3(v.x,-v.y,-v.z))
    vector(Quaternion.axis_angle(Vec3(0,1,0),half).rotate(v),Vec3(-v.x,v.y,-v.z))
    vector(Quaternion.axis_angle(Vec3(0,0,1),half).rotate(v),Vec3(-v.x,-v.y,v.z))
    assert_equal(count,90);print("Independent Rodrigues",count,"cases: principal/general axes, 0/90/180 degrees, inverse/norm/axis projection and scale identities passed")
@fieldwise_init
struct GuardedVector(ImplicitlyCopyable,Movable):
    var before: Float64
    var value: Vec3
    var after: Float64
def zero_and_neighbor_isolation() raises:
    var v=Vec3(.37,-2,4)
    vector(Vec3(0,0,0).unit(),Vec3(0,0,0));vector(Vec3(0,1e-7,0).unit(),Vec3(0,0,0));vector(Vec3(0,1e-5,0).unit(),Vec3(0,1,0))
    vector(Quaternion.axis_angle(Vec3(0,0,0),.61).rotate(v),v)
    vector(Quaternion.axis_angle(Vec3(0,0,1e-13),.61).rotate(v),rodrigues(Vec3(0,0,1),v,.61))
    vector(Quaternion(0,0,0,0).rotate(v),v);vector(Quaternion(1e-15,0,0,0).rotate(v),v)
    # Atlas has three named fields, not HEPJo's fourth padding lane. Protect
    # logical arithmetic and adjacent fields without adopting that layout.
    for marker in [Float64(1e30),Float64(-1e20)]:
        var guarded=GuardedVector(marker,v,-marker);var shifted=guarded.value+Vec3(.23,-.47,.91)
        near(shifted.dot(shifted),scalar_dot(shifted,shifted));near(shifted.length()*shifted.length(),scalar_dot(shifted,shifted))
        assert_equal(guarded.before,marker);assert_equal(guarded.after,-marker);vector(guarded.value,v)
    print("Zero/near-zero documented fallbacks and three-coordinate/neighbor-canary isolation passed")
def main() raises:
    rotation_identities();zero_and_neighbor_isolation()
    vector(Quaternion.axis_angle(Vec3(0,0,1e-8),1.5707963267948966).rotate(Vec3(1,0,0)),Vec3(0,1,0))
    print("Independent CPU vector/quaternion regression passed; small nonzero-axis probe is now a passing regression")
