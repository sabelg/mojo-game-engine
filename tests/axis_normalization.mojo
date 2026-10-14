"""Independent Decimal-normalized fixtures and scalar Rodrigues oracle.

Directions were computed at 1200 decimal digits from exact Float64 inputs,
then rounded once to Float64. No production normalization is used by the oracle.
Fixture inputs cover binary64 subnormals through maximum finite components.
"""
from std.collections import List
from std.math import sin, cos, isfinite
from std.testing import assert_true, assert_equal
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion

@fieldwise_init
struct AxisCase(ImplicitlyCopyable, Movable):
    var axis: Vec3
    var direction: Vec3

def fixtures() -> List[AxisCase]:
    return [
        AxisCase(Vec3(0.0,0.0,1e-08),Vec3(0.0,0.0,1.0)),
        AxisCase(Vec3(0.0,0.0,1e-13),Vec3(0.0,0.0,1.0)),
        AxisCase(Vec3(0.0,0.0,5e-324),Vec3(0.0,0.0,1.0)),
        AxisCase(Vec3(5e-324,1e-323,-1.5e-323),Vec3(0.2672612419124244,0.5345224838248488,-0.8017837257372732)),
        AxisCase(Vec3(2.2250738585072014e-308,2.2250738585072014e-308,-2.2250738585072014e-308),Vec3(0.5773502691896257,0.5773502691896257,-0.5773502691896257)),
        AxisCase(Vec3(1.7976931348623157e+308,1.7976931348623157e+308,-1.7976931348623157e+308),Vec3(0.5773502691896257,0.5773502691896257,-0.5773502691896257)),
        AxisCase(Vec3(1.7976931348623157e+308,2.2250738585072014e-308,5e-324),Vec3(1.0,0.0,0.0)),
        AxisCase(Vec3(2e-300,-3e-300,5e-300),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e-200,-3e-200,5e-200),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e-100,-3e-100,5e-100),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e-12,-3e-12,5e-12),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e-08,-3.0000000000000004e-08,5e-08),Vec3(0.3244428422615251,-0.4866642633922877,0.8111071056538126)),
        AxisCase(Vec3(2e-06,-3e-06,4.9999999999999996e-06),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538126)),
        AxisCase(Vec3(2.0,-3.0,5.0),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e+100,-3.0000000000000002e+100,5e+100),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e+200,-3e+200,4.9999999999999995e+200),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(2e+300,-3e+300,5e+300),Vec3(0.3244428422615251,-0.48666426339228763,0.8111071056538127)),
        AxisCase(Vec3(-0.0,-0.0,-1e-08),Vec3(-0.0,-0.0,-1.0)),
        AxisCase(Vec3(-0.0,-0.0,-1e-13),Vec3(-0.0,-0.0,-1.0)),
        AxisCase(Vec3(-0.0,-0.0,-5e-324),Vec3(-0.0,-0.0,-1.0)),
        AxisCase(Vec3(-5e-324,-1e-323,1.5e-323),Vec3(-0.2672612419124244,-0.5345224838248488,0.8017837257372732)),
        AxisCase(Vec3(-2.2250738585072014e-308,-2.2250738585072014e-308,2.2250738585072014e-308),Vec3(-0.5773502691896257,-0.5773502691896257,0.5773502691896257)),
        AxisCase(Vec3(-1.7976931348623157e+308,-1.7976931348623157e+308,1.7976931348623157e+308),Vec3(-0.5773502691896257,-0.5773502691896257,0.5773502691896257)),
        AxisCase(Vec3(-1.7976931348623157e+308,-2.2250738585072014e-308,-5e-324),Vec3(-1.0,-0.0,-0.0)),
        AxisCase(Vec3(-2e-300,3e-300,-5e-300),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e-200,3e-200,-5e-200),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e-100,3e-100,-5e-100),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e-12,3e-12,-5e-12),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e-08,3.0000000000000004e-08,-5e-08),Vec3(-0.3244428422615251,0.4866642633922877,-0.8111071056538126)),
        AxisCase(Vec3(-2e-06,3e-06,-4.9999999999999996e-06),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538126)),
        AxisCase(Vec3(-2.0,3.0,-5.0),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e+100,3.0000000000000002e+100,-5e+100),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e+200,3e+200,-4.9999999999999995e+200),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
        AxisCase(Vec3(-2e+300,3e+300,-5e+300),Vec3(-0.3244428422615251,0.48666426339228763,-0.8111071056538127)),
    ]
def near(a: Float64, b: Float64) raises:
    assert_true(isfinite(a) and isfinite(b))
    assert_true(abs(a-b) <= 1e-11*(1+abs(b)))

def vector(a: Vec3, b: Vec3) raises:
    near(a.x,b.x); near(a.y,b.y); near(a.z,b.z)

def dot(a: Vec3,b: Vec3) -> Float64:
    return a.x*b.x+a.y*b.y+a.z*b.z

def oracle(n: Vec3,v: Vec3,angle: Float64) -> Vec3:
    var c=cos(angle); var s=sin(angle); var p=dot(n,v)*(1-c)
    return Vec3(c*v.x+s*(n.y*v.z-n.z*v.y)+n.x*p,
                c*v.y+s*(n.z*v.x-n.x*v.z)+n.y*p,
                c*v.z+s*(n.x*v.y-n.y*v.x)+n.z*p)

def check_rotation(q: Quaternion, n: Vec3, angle: Float64, v: Vec3) raises:
    near(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w,1)
    var actual=q.rotate(v)
    vector(actual,oracle(n,v,angle))
    near(dot(actual,actual),dot(v,v))
    near(dot(n,actual),dot(n,v))
    # Conjugation is an independent inverse (no second axis normalization).
    vector(Quaternion(-q.x,-q.y,-q.z,q.w).rotate(actual),v)

def invalid(q: Quaternion) raises:
    assert_true(q.x != q.x and q.y != q.y and q.z != q.z and q.w != q.w)

def special_contract() raises:
    var zero=Vec3(-0.0,0.0,-0.0)
    var v=Vec3(.37,-2,4)
    for a in [Float64(.61),Float64("nan"),Float64("inf"),Float64("-inf")]:
        var q=Quaternion.axis_angle(zero,a)
        assert_equal(q.x,Float64(0));assert_equal(q.y,Float64(0));assert_equal(q.z,Float64(0));assert_equal(q.w,Float64(1))
        vector(q.rotate(v),v)
    for value in [Float64("nan"),Float64("inf"),Float64("-inf")]:
        for a in [Vec3(value,0,0),Vec3(0,value,1),Vec3(1,0,value)]:
            invalid(Quaternion.axis_angle(a,.61));invalid(Quaternion.axis_angle(a,0))
        invalid(Quaternion.axis_angle(Vec3(0,0,1),value))
    # Half of the least subnormal rounds to zero: no representable increment.
    var least=Float64(5e-324)
    assert_equal(least*.5,Float64(0))
    var lost=Quaternion.axis_angle(Vec3(0,0,1),least)
    assert_equal(lost.z,Float64(0));assert_equal(lost.w,Float64(1))
    var retained=Quaternion.axis_angle(Vec3(0,0,1),Float64(1e-323))
    assert_equal(retained.z,least)
    # A direction ratio below the least subnormal is unrepresentable.
    var mixed=Quaternion.axis_angle(Vec3(1.7976931348623157e308,2.2250738585072014e-308,5e-324),.61)
    assert_equal(mixed.y,Float64(0));assert_equal(mixed.z,Float64(0))
    print("Zero/signed-zero identity, non-finite all-NaN, half-angle/direction representation limits passed")

def main() raises:
    var cases=fixtures();var count=0
    for f in cases:
        for angle in [Float64(0),Float64(1.5707963267948966),Float64(3.141592653589793),Float64(-.37),Float64(.61)]:
            var q=Quaternion.axis_angle(f.axis,angle)
            for v in [Vec3(1,0,0),Vec3(.37,-2,4),Vec3(-5,.7,2.3)]:
                check_rotation(q,f.direction,angle,v)
                vector(Quaternion.axis_angle(f.axis*(-1),-angle).rotate(v),q.rotate(v))
                vector(Quaternion.axis_angle(f.axis,-angle).rotate(q.rotate(v)),v)
                count+=1
    vector(Quaternion.axis_angle(Vec3(0,0,1e-8),1.5707963267948966).rotate(Vec3(1,0,0)),Vec3(0,1,0))
    special_contract()
    print("Independent extreme-axis CPU Rodrigues:",len(cases),"axes",count,"rotation cases passed")
