"""2D vectors, transforms, and inclusive axis-aligned collision queries."""
from std.math import sqrt, sin, cos

@fieldwise_init
struct Vec2(ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64

    def __add__(self, b: Self) -> Self:
        return Self(self.x+b.x, self.y+b.y)

    def __sub__(self, b: Self) -> Self:
        return Self(self.x-b.x, self.y-b.y)

    def __mul__(self, scale: Float64) -> Self:
        return Self(self.x*scale, self.y*scale)

    def dot(self, b: Self) -> Float64:
        return self.x*b.x+self.y*b.y

    def length(self) -> Float64:
        return sqrt(self.dot(self))

    def unit(self) -> Self:
        var magnitude = self.length()
        if magnitude <= 1e-12: return Self(0, 0)
        return self*(1/magnitude)

@fieldwise_init
struct Transform2D(ImplicitlyCopyable, Movable):
    var position: Vec2
    var rotation: Float64
    var scale: Vec2

    def apply(self, point: Vec2) -> Vec2:
        var x = point.x*self.scale.x
        var y = point.y*self.scale.y
        return self.position+Vec2(x*cos(self.rotation)-y*sin(self.rotation), x*sin(self.rotation)+y*cos(self.rotation))

@fieldwise_init
struct AABB(ImplicitlyCopyable, Movable):
    """Center and nonnegative half extents. Touching edges overlap."""
    var center: Vec2
    var half: Vec2

    def contains(self, point: Vec2) -> Bool:
        return abs(point.x-self.center.x) <= self.half.x and abs(point.y-self.center.y) <= self.half.y

    def overlaps(self, other: Self) -> Bool:
        return abs(self.center.x-other.center.x) <= self.half.x+other.half.x and abs(self.center.y-other.center.y) <= self.half.y+other.half.y
