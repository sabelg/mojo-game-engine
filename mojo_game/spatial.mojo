"""World bounds, ray picking and six-plane view-frustum culling."""
from std.collections import Array
from .math3d import Vec3
from .transform3d import Mat4

@fieldwise_init
struct Bounds3D(ImplicitlyCopyable, Movable):
    var minimum: Vec3
    var maximum: Vec3

    def transformed(self, matrix: Mat4) -> Self:
        var low = matrix.point(self.minimum)
        var high = low
        for i in range(8):
            var p = matrix.point(Vec3(self.maximum.x if i&1 else self.minimum.x,self.maximum.y if i&2 else self.minimum.y,self.maximum.z if i&4 else self.minimum.z))
            low = Vec3(min(low.x,p.x),min(low.y,p.y),min(low.z,p.z))
            high = Vec3(max(high.x,p.x),max(high.y,p.y),max(high.z,p.z))
        return Self(low,high)

    def ray(self, origin: Vec3, direction: Vec3, maximum: Float64 = 10000) -> Float64:
        """Returns distance for unit directions; -1 on miss, 0 when inside."""
        var near: Float64 = 0
        var far = maximum
        var starts: List[Float64] = [origin.x,origin.y,origin.z]
        var dirs: List[Float64] = [direction.x,direction.y,direction.z]
        var lows: List[Float64] = [self.minimum.x,self.minimum.y,self.minimum.z]
        var highs: List[Float64] = [self.maximum.x,self.maximum.y,self.maximum.z]
        for i in range(3):
            if abs(dirs[i]) < 1e-12:
                if starts[i] < lows[i] or starts[i] > highs[i]: return -1
            else:
                var a = (lows[i]-starts[i])/dirs[i]
                var b = (highs[i]-starts[i])/dirs[i]
                near = max(near,min(a,b))
                far = min(far,max(a,b))
                if near > far: return -1
        return near

struct Frustum:
    var coefficients: Array[Float64,24]

    def __init__(out self, matrix: Mat4):
        self.coefficients = Array[Float64,24](fill=0)
        for plane in range(6):
            var axis = plane//2
            var sign: Float64 = 1 if plane%2 == 0 else -1
            for col in range(4):
                self.coefficients[plane*4+col] = matrix.data[col*4+3]+sign*matrix.data[col*4+axis]

    def visible(self, bounds: Bounds3D, origin: Vec3 = Vec3(0,0,0)) -> Bool:
        for p in range(6):
            var x = self.coefficients[p*4]
            var y = self.coefficients[p*4+1]
            var z = self.coefficients[p*4+2]
            var vx = bounds.maximum.x if x >= 0 else bounds.minimum.x
            var vy = bounds.maximum.y if y >= 0 else bounds.minimum.y
            var vz = bounds.maximum.z if z >= 0 else bounds.minimum.z
            if x*(vx-origin.x)+y*(vy-origin.y)+z*(vz-origin.z)+self.coefficients[p*4+3] < 0: return False
        return True
