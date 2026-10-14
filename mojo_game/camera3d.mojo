"""Third-person orbit camera with sphere obstruction and floating-origin views."""
from std.math import isfinite,sin,cos,exp
from .math3d import Vec3
from .transform3d import Mat4
from .character3d import CollisionWorld3D

struct ThirdPersonCamera(ImplicitlyCopyable,Movable):
    var yaw: Float64
    var pitch: Float64
    var distance: Float64
    var actual_distance: Float64
    var radius: Float64
    var height: Float64
    var position: Vec3
    var target: Vec3
    def __init__(out self,distance: Float64=5) raises:
        if not isfinite(distance) or distance<.5 or distance>100:raise Error("Invalid third-person camera distance")
        self.yaw=0
        self.pitch=.3
        self.distance=distance
        self.actual_distance=distance
        self.radius=.2
        self.height=1.3
        self.position=Vec3(0,0,0)
        self.target=Vec3(0,0,0)
    def orbit(mut self,dx: Float64,dy: Float64,zoom: Float64=0) raises:
        if not isfinite(dx) or not isfinite(dy) or not isfinite(zoom):raise Error("Invalid camera orbit input")
        self.yaw+=dx
        self.pitch=max(-.8,min(1.3,self.pitch+dy))
        self.distance=max(.5,min(25.0,self.distance-zoom))
    def direction(self) -> Vec3:
        return Vec3(sin(self.yaw)*cos(self.pitch),sin(self.pitch),cos(self.yaw)*cos(self.pitch))
    def movement(self,right: Float64,forward: Float64) -> Vec3:
        var result=Vec3(cos(self.yaw),0,-sin(self.yaw))*right-Vec3(sin(self.yaw),0,cos(self.yaw))*forward
        return result.unit()*min(1.0,result.length())
    def update(mut self,world: CollisionWorld3D,feet: Vec3,dt: Float64) raises:
        if not isfinite(dt) or dt<0 or dt>.25 or self.radius<=0 or self.distance<.5:raise Error("Invalid camera update")
        self.target=feet+Vec3(0,self.height,0)
        var direction=self.direction()
        var wanted=self.distance
        var start=self.target-Vec3(0,self.radius,0)
        var hit=world.sweep(start,direction*self.distance,self.radius,self.radius*2)
        if hit:wanted=max(.05,self.distance*hit.value().fraction-.02)
        if wanted<self.actual_distance:self.actual_distance=wanted
        else:self.actual_distance=min(wanted,self.actual_distance+(wanted-self.actual_distance)*(1-exp(-8*dt)))
        self.position=self.target+direction*self.actual_distance
    def view(self,origin: Vec3=Vec3(0,0,0)) raises -> Mat4:
        return Mat4.look_at(self.position-origin,self.target-origin)
