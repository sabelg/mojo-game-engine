"""Camera-frustum directional cascades, overlap and world-grid stabilization.

Matrices operate on positions relative to draw origin. World origin is used only
for double-precision texel alignment; no absolute coordinates reach the GPU.
Caster padding bounds how far light-space occluders outside the view are included.
"""
from .math3d import Vec3
from .transform3d import Mat4
from std.math import isfinite,ceil,round,pow

def unproject(matrix: Mat4,x: Float64,y: Float64,z: Float64) raises -> Vec3:
    var w=matrix.data[3]*x+matrix.data[7]*y+matrix.data[11]*z+matrix.data[15]
    if not isfinite(w) or abs(w)<1e-12:raise Error("Unbounded directional shadow frustum")
    return matrix.point(Vec3(x,y,z))*(1/w)

struct DirectionalShadows3D(Copyable,Movable):
    var count: Int
    var distance: Float64
    var split_mix: Float64
    var caster_padding: Float64
    var stabilize: Bool
    var matrices: List[Mat4]
    var splits: List[Float64]
    var forward: Vec3
    var camera_offset: Vec3
    var cull_matrix: Mat4

    def __init__(out self,count: Int=4,distance: Float64=256,split_mix: Float64=.65,caster_padding: Float64=80,stabilize: Bool=True) raises:
        if (count!=2 and count!=4) or not isfinite(distance) or distance<1 or distance>16384 or not isfinite(split_mix) or split_mix<0 or split_mix>1 or not isfinite(caster_padding) or caster_padding<1 or caster_padding>1024:raise Error("Invalid directional shadow quality settings")
        self.count=count
        self.distance=distance
        self.split_mix=split_mix
        self.caster_padding=caster_padding
        self.stabilize=stabilize
        self.matrices=List[Mat4]()
        self.splits=List[Float64]()
        self.forward=Vec3(0,0,-1)
        self.camera_offset=Vec3(0,0,0)
        self.cull_matrix=Mat4()

    def fit(self,near: List[Vec3],far: List[Vec3],start: Float64,end: Float64,sun: Vec3,origin: Vec3) raises -> Mat4:
        var points=List[Vec3]()
        var center=Vec3(0,0,0)
        for i in range(4):
            points.append(near[i]+(far[i]-near[i])*start)
            points.append(near[i]+(far[i]-near[i])*end)
        for point in points:center=center+point*(1.0/8)
        var radius: Float64=.01
        for point in points:radius=max(radius,(point-center).length())
        radius=ceil(radius*16)/16
        radius+=radius*2/2048
        var up=Vec3(0,1,0) if abs(sun.y)<.95 else Vec3(0,0,1)
        var basis=Mat4.look_at(sun,Vec3(0,0,0),up)
        if self.stabilize:
            var right=Vec3(basis.data[0],basis.data[4],basis.data[8])
            var vertical=Vec3(basis.data[1],basis.data[5],basis.data[9])
            var texel=2*radius/2048
            var world=center+origin
            var x=right.dot(world)
            var y=vertical.dot(world)
            center=center+right*(round(x/texel)*texel-x)+vertical*(round(y/texel)*texel-y)
        return Mat4.orthographic(radius,.1,2*(radius+self.caster_padding))*Mat4.look_at(center+sun*(radius+self.caster_padding),center,up)

    def prepare(mut self,projection: Mat4,near: Float64,far: Float64,sun: Vec3,forward: Vec3,camera_offset: Vec3=Vec3(0,0,0),world_origin: Vec3=Vec3(0,0,0)) raises:
        if (self.count!=2 and self.count!=4) or not isfinite(self.distance) or self.distance<1 or self.distance>16384 or not isfinite(self.split_mix) or self.split_mix<0 or self.split_mix>1 or not isfinite(self.caster_padding) or self.caster_padding<1 or self.caster_padding>1024:raise Error("Invalid directional shadow quality settings")
        if not isfinite(near) or not isfinite(far) or near<=0 or far<=near or min(far,self.distance)<=near:raise Error("Invalid directional shadow camera range")
        for value in projection.data:
            if not isfinite(value):raise Error("Non-finite directional shadow projection")
        for point in [sun,forward,camera_offset,world_origin]:
            if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z):raise Error("Non-finite directional shadow vector")
        if sun.length()<.001 or abs(forward.length()-1)>.0001:raise Error("Invalid directional shadow light/camera direction")
        var inverse=projection.inverse()
        var first=List[Vec3]()
        var last=List[Vec3]()
        for i in range(4):
            var x=Float64(1 if i&1 else -1)
            var y=Float64(1 if i&2 else -1)
            first.append(unproject(inverse,x,y,-1))
            last.append(unproject(inverse,x,y,1))
            if abs((first[i]-camera_offset).dot(forward)-near)>max(.001,near*.001) or abs((last[i]-camera_offset).dot(forward)-far)>max(.001,far*.001):raise Error("Directional shadow camera range/direction does not match projection")
        var end=min(far,self.distance)
        var matrices=List[Mat4]()
        var splits=List[Float64]()
        for i in range(self.count):
            var fraction=Float64(i+1)/Float64(self.count)
            var linear=near+(end-near)*fraction
            var logarithmic=near*pow(end/near,fraction)
            splits.append(linear*(1-self.split_mix)+logarithmic*self.split_mix)
            var start=near
            if i>0:
                var previous=near if i==1 else splits[i-2]
                start=splits[i-1]-(splits[i-1]-previous)*.1
            matrices.append(self.fit(first,last,(start-near)/(far-near),(splits[i]-near)/(far-near),sun.unit(),world_origin))
        var cull=self.fit(first,last,0,(end-near)/(far-near),sun.unit(),world_origin)
        self.matrices=matrices^
        self.splits=splits^
        self.forward=forward
        self.camera_offset=camera_offset
        self.cull_matrix=cull
