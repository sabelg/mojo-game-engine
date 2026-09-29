"""3D vectors, a toroidal world, swept collisions, and perspective clipping."""
from std.math import sin, cos, sqrt

comptime WORLD = 2400.0
comptime FOCAL = 720.0

@fieldwise_init
struct Vec3(ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64
    var z: Float64

    def __add__(self, b: Self) -> Self:
        return Self(self.x+b.x, self.y+b.y, self.z+b.z)

    def __sub__(self, b: Self) -> Self:
        return Self(self.x-b.x, self.y-b.y, self.z-b.z)

    def __mul__(self, s: Float64) -> Self:
        return Self(self.x*s, self.y*s, self.z*s)

    def dot(self, b: Self) -> Float64:
        return self.x*b.x+self.y*b.y+self.z*b.z

    def length(self) -> Float64:
        return sqrt(self.dot(self))

    def unit(self) -> Self:
        var length = self.length()
        if length < 0.000001: return Self(0, 0, 0)
        return self*(1/length)

    def cross(self, b: Self) -> Self:
        return Self(self.y*b.z-self.z*b.y, self.z*b.x-self.x*b.z, self.x*b.y-self.y*b.x)

def wrap(value: Float64, limit: Float64 = WORLD) -> Float64:
    return value - (value // limit)*limit

def wrapped(p: Vec3) -> Vec3:
    return Vec3(wrap(p.x), wrap(p.y), wrap(p.z))

def displacement(origin: Vec3, target: Vec3) -> Vec3:
    var d = target-origin
    return Vec3(wrap(d.x+WORLD/2)-WORLD/2, wrap(d.y+WORLD/2)-WORLD/2, wrap(d.z+WORLD/2)-WORLD/2)

def forward(yaw: Float64, pitch: Float64) -> Vec3:
    return Vec3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))

def right(yaw: Float64) -> Vec3:
    return Vec3(cos(yaw), 0, -sin(yaw))

def up(yaw: Float64, pitch: Float64) -> Vec3:
    return forward(yaw, pitch).cross(right(yaw))

def segment_distance(a: Vec3, b: Vec3) -> Float64:
    # Distance from the origin to a segment (relative projectile motion).
    var d = b-a
    var denom = d.dot(d)
    if denom < 0.000001: return a.length()
    var t = max(0.0, min(1.0, -a.dot(d)/denom))
    return (a+d*t).length()

@fieldwise_init
struct Camera(ImplicitlyCopyable, Movable):
    var origin: Vec3
    var offset: Vec3
    var forward_axis: Vec3
    var right_axis: Vec3
    var up_axis: Vec3

    @staticmethod
    def chase(position: Vec3, yaw: Float64, pitch: Float64) -> Self:
        var f = forward(yaw, pitch)
        var r = right(yaw)
        var u = up(yaw, pitch)
        var view = (f-u*0.18).unit()
        return Self(position, f*(-220)+u*85, view, r, view.cross(r))

    def relative(self, p: Vec3) -> Vec3:
        var d = p-self.offset
        return Vec3(d.dot(self.right_axis), d.dot(self.up_axis), d.dot(self.forward_axis))

    def world(self, p: Vec3) -> Vec3:
        return self.relative(displacement(self.origin, p))

def plane(p: Vec3, index: Int) -> Float64:
    if index == 0: return p.z-8
    if index == 1: return 2800-p.z
    if index == 2: return p.z*550/FOCAL+p.x
    if index == 3: return p.z*550/FOCAL-p.x
    if index == 4: return p.z*380/FOCAL+p.y
    return p.z*380/FOCAL-p.y

def clip_segment(mut a: Vec3, mut b: Vec3) -> Bool:
    # Clip before division, including lines crossing the camera's near plane.
    for i in range(6):
        var da = plane(a, i)
        var db = plane(b, i)
        if da < 0 and db < 0: return False
        if da < 0 or db < 0:
            var intersection = a+(b-a)*(da/(da-db))
            if da < 0: a = intersection
            else: b = intersection
    return True
