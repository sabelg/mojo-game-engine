"""Right-handed transforms. Column-major matrices, column vectors, camera -Z."""
from std.collections import Array
from std.math import sin, cos, sqrt, tan
from .math3d import Vec3

struct Quaternion(ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64
    var z: Float64
    var w: Float64

    def __init__(out self, x: Float64 = 0, y: Float64 = 0, z: Float64 = 0, w: Float64 = 1):
        self.x = x
        self.y = y
        self.z = z
        self.w = w

    @staticmethod
    def axis_angle(axis: Vec3, angle: Float64) -> Self:
        if axis.length() < 1e-12: return Self()
        var n = axis.unit()*sin(angle/2)
        return Self(n.x, n.y, n.z, cos(angle/2))

    def normalized(self) -> Self:
        var length = sqrt(self.x*self.x+self.y*self.y+self.z*self.z+self.w*self.w)
        if length < 1e-12: return Self()
        return Self(self.x/length, self.y/length, self.z/length, self.w/length)

    def __mul__(self, b: Self) -> Self:
        return Self(self.w*b.x+self.x*b.w+self.y*b.z-self.z*b.y,
                    self.w*b.y-self.x*b.z+self.y*b.w+self.z*b.x,
                    self.w*b.z+self.x*b.y-self.y*b.x+self.z*b.w,
                    self.w*b.w-self.x*b.x-self.y*b.y-self.z*b.z)

    def rotate(self, v: Vec3) -> Vec3:
        var q = self.normalized()
        var xyz = Vec3(q.x, q.y, q.z)
        var t = xyz.cross(v)*2
        return v+t*q.w+xyz.cross(t)

    @staticmethod
    def nlerp(a: Self, b: Self, t: Float64) -> Self:
        var sign: Float64 = 1
        if a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w < 0: sign = -1
        var f = max(0.0, min(1.0, t))
        return Self(a.x*(1-f)+b.x*f*sign, a.y*(1-f)+b.y*f*sign, a.z*(1-f)+b.z*f*sign, a.w*(1-f)+b.w*f*sign).normalized()

struct Mat4(ImplicitlyCopyable, Movable):
    var data: Array[Float64, 16]

    def __init__(out self):
        self.data = Array[Float64, 16](fill=0)
        for i in range(4): self.data[i*5] = 1

    def __init__(out self, *, copy: Self):
        self.data = copy.data.copy()

    def __mul__(self, b: Self) -> Self:
        var result = Self()
        for c in range(4):
            for r in range(4):
                var value: Float64 = 0
                for k in range(4): value += self.data[k*4+r]*b.data[c*4+k]
                result.data[c*4+r] = value
        return result

    def point(self, p: Vec3) -> Vec3:
        return Vec3(Float64(self.data[0])*p.x+Float64(self.data[4])*p.y+Float64(self.data[8])*p.z+Float64(self.data[12]),
                    Float64(self.data[1])*p.x+Float64(self.data[5])*p.y+Float64(self.data[9])*p.z+Float64(self.data[13]),
                    Float64(self.data[2])*p.x+Float64(self.data[6])*p.y+Float64(self.data[10])*p.z+Float64(self.data[14]))

    @staticmethod
    def perspective(fov: Float64, aspect: Float64, near: Float64, far: Float64) raises -> Self:
        if fov <= 0 or fov >= 3.14 or aspect <= 0 or near <= 0 or far <= near:
            raise Error("Invalid perspective projection")
        var m = Self()
        m.data = Array[Float64, 16](fill=0)
        var f = 1/tan(fov/2)
        m.data[0] = Float64(f/aspect)
        m.data[5] = Float64(f)
        m.data[10] = Float64((far+near)/(near-far))
        m.data[11] = -1
        m.data[14] = Float64(2*far*near/(near-far))
        return m

    @staticmethod
    def orthographic(size: Float64, near: Float64, far: Float64) raises -> Self:
        if size <= 0 or far <= near: raise Error("Invalid orthographic projection")
        var m = Self()
        m.data[0] = Float64(1/size)
        m.data[5] = Float64(1/size)
        m.data[10] = Float64(-2/(far-near))
        m.data[14] = Float64(-(far+near)/(far-near))
        return m

    @staticmethod
    def look_at(eye: Vec3, target: Vec3, up: Vec3 = Vec3(0, 1, 0)) raises -> Self:
        var f = (target-eye).unit()
        var s = f.cross(up).unit()
        if f.length() < 0.5 or s.length() < 0.5: raise Error("Degenerate camera basis")
        var u = s.cross(f)
        var m = Self()
        m.data[0] = Float64(s.x)
        m.data[4] = Float64(s.y)
        m.data[8] = Float64(s.z)
        m.data[1] = Float64(u.x)
        m.data[5] = Float64(u.y)
        m.data[9] = Float64(u.z)
        m.data[2] = Float64(-f.x)
        m.data[6] = Float64(-f.y)
        m.data[10] = Float64(-f.z)
        m.data[12] = Float64(-s.dot(eye))
        m.data[13] = Float64(-u.dot(eye))
        m.data[14] = Float64(f.dot(eye))
        return m

struct Transform3D(ImplicitlyCopyable, Movable):
    var position: Vec3
    var rotation: Quaternion
    var scale: Vec3

    def __init__(out self, position: Vec3 = Vec3(0, 0, 0), rotation: Quaternion = Quaternion(), scale: Vec3 = Vec3(1, 1, 1)):
        self.position = position
        self.rotation = rotation
        self.scale = scale

    def matrix(self) -> Mat4:
        var x = self.rotation.rotate(Vec3(self.scale.x, 0, 0))
        var y = self.rotation.rotate(Vec3(0, self.scale.y, 0))
        var z = self.rotation.rotate(Vec3(0, 0, self.scale.z))
        var m = Mat4()
        m.data[0] = Float64(x.x)
        m.data[1] = Float64(x.y)
        m.data[2] = Float64(x.z)
        m.data[4] = Float64(y.x)
        m.data[5] = Float64(y.y)
        m.data[6] = Float64(y.z)
        m.data[8] = Float64(z.x)
        m.data[9] = Float64(z.y)
        m.data[10] = Float64(z.z)
        m.data[12] = Float64(self.position.x)
        m.data[13] = Float64(self.position.y)
        m.data[14] = Float64(self.position.z)
        return m


def gpu_matrix(matrix: Mat4, origin: Vec3 = Vec3(0, 0, 0)) -> Array[Float32, 16]:
    var data = Array[Float32, 16](fill=0)
    for i in range(16): data[i] = Float32(matrix.data[i])
    data[12] = Float32(matrix.data[12]-origin.x)
    data[13] = Float32(matrix.data[13]-origin.y)
    data[14] = Float32(matrix.data[14]-origin.z)
    return data^
