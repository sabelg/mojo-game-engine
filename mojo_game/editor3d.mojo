"""Scene editing with bounded undo/redo and free-flight camera controls."""
from std.math import sin, cos, tan
from .math3d import Vec3
from .transform3d import Mat4, Quaternion
from .scene3d import Scene3D
from .input import Input
from .durableio import object_id

struct FlyCamera(ImplicitlyCopyable, Movable):
    var position: Vec3
    var yaw: Float64
    var pitch: Float64
    var speed: Float64

    def __init__(out self, position: Vec3 = Vec3(80,45,100)):
        self.position = position
        self.yaw = 0
        self.pitch = -0.3
        self.speed = 30

    def direction(self) -> Vec3:
        return Vec3(sin(self.yaw)*cos(self.pitch),sin(self.pitch),-cos(self.yaw)*cos(self.pitch))

    def update(mut self, input: Input, dt: Float64):
        if input.mouse_down(3):
            self.yaw += Float64(input.mouse_dx)*0.003
            self.pitch = max(-1.5,min(1.5,self.pitch-Float64(input.mouse_dy)*0.003))
        self.yaw += input.axis(13,15)*dt*1.4
        self.pitch = max(-1.5,min(1.5,self.pitch+input.axis(14,12)*dt*1.4))
        var right = Vec3(cos(self.yaw),0,sin(self.yaw))
        var movement = self.direction()*input.axis(22,26)+right*input.axis(4,7)+Vec3(0,input.axis(20,8),0)
        var multiplier: Float64 = 8 if input.down(225) else 1
        self.position = self.position+movement.unit()*(self.speed*dt*multiplier)

    def screen_ray(self, x: Int, y: Int, width: Int, height: Int, fov: Float64 = 1.04719755) -> Vec3:
        var forward = self.direction()
        var right = Vec3(cos(self.yaw),0,sin(self.yaw))
        var up = right.cross(forward)
        var aspect = Float64(max(1,width))/Float64(max(1,height))
        var sx = (2*Float64(x)/Float64(max(1,width))-1)*aspect*tan(fov/2)
        var sy = (1-2*Float64(y)/Float64(max(1,height)))*tan(fov/2)
        return (forward+right*sx+up*sy).unit()

    def view(self) raises -> Mat4:
        return Mat4.look_at(Vec3(0,0,0),self.direction())

struct SceneEditor:
    var selected: Int
    var undo_stack: List[Scene3D]
    var redo_stack: List[Scene3D]
    var status: String

    def __init__(out self):
        self.selected = 0
        self.undo_stack = List[Scene3D]()
        self.redo_stack = List[Scene3D]()
        self.status = "READY"

    def checkpoint(mut self, scene: Scene3D):
        if len(self.undo_stack) >= 32:
            var trimmed = List[Scene3D]()
            for i in range(1,len(self.undo_stack)): trimmed.append(self.undo_stack[i].copy())
            self.undo_stack = trimmed^
        self.undo_stack.append(scene.copy())
        self.redo_stack.clear()

    def undo(mut self, mut scene: Scene3D):
        if len(self.undo_stack) == 0: return
        self.redo_stack.append(scene.copy())
        scene = self.undo_stack.pop()
        self.status = "UNDO"

    def redo(mut self, mut scene: Scene3D):
        if len(self.redo_stack) == 0: return
        self.undo_stack.append(scene.copy())
        scene = self.redo_stack.pop()
        self.status = "REDO"

    def update(mut self, mut scene: Scene3D, input: Input) raises:
        if input.pressed(43) and len(scene.nodes) > 0:
            for _ in range(len(scene.nodes)):
                self.selected = (self.selected+1)%len(scene.nodes)
                if scene.valid(self.selected): break
        if input.pressed(29): self.undo(scene)
        if input.pressed(28): self.redo(scene)
        if not scene.valid(self.selected): return
        var delta = Vec3(Float64(Int(input.pressed(79))-Int(input.pressed(80))),Float64(Int(input.pressed(75))-Int(input.pressed(78))),Float64(Int(input.pressed(81))-Int(input.pressed(82))))
        if delta.length() > 0:
            self.checkpoint(scene)
            scene.nodes[self.selected].transform.position = scene.nodes[self.selected].transform.position+delta
            self.status = "TRANSFORM UPDATED"
        if input.pressed(21):
            self.checkpoint(scene)
            scene.nodes[self.selected].transform.rotation = Quaternion.axis_angle(Vec3(0,1,0),0.261799)*scene.nodes[self.selected].transform.rotation
        if input.pressed(46) or input.pressed(45):
            self.checkpoint(scene)
            var scale: Float64 = 1.1 if input.pressed(46) else 1/1.1
            scene.nodes[self.selected].transform.scale = scene.nodes[self.selected].transform.scale*scale
            self.status = "SCALE UPDATED"
        if input.pressed(27):
            self.checkpoint(scene)
            scene.remove(self.selected)
            self.status = "OBJECT DELETED"
        elif input.pressed(5):
            self.checkpoint(scene)
            var node = scene.nodes[self.selected].copy()
            node.name += " COPY"
            node.persistent_id=object_id()
            node.transform.position.x += 3
            self.selected = scene.add(node^)
            self.status = "OBJECT DUPLICATED"
