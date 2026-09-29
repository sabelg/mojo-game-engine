"""Cached mesh assets and culling-aware scene submission.

Scene mesh indices address this table. Populate assets in a stable order when
loading saved scenes. Graphics3D owns GPU resources; close this cache first.
"""
from .mesh import Mesh, load_obj
from .graphics3d import Graphics3D
from .scene3d import Scene3D
from .spatial import Bounds3D, Frustum
from .math3d import Vec3
from .transform3d import Mat4

struct Assets3D:
    var keys: List[String]
    var handles: List[Int]
    var bounds: List[Bounds3D]

    def __init__(out self):
        self.keys = List[String]()
        self.handles = List[Int]()
        self.bounds = List[Bounds3D]()

    def find(self, key: String) -> Int:
        for i in range(len(self.keys)):
            if self.keys[i] == key: return i
        return -1

    def add(mut self, device: Graphics3D, var key: String, mesh: Mesh) raises -> Int:
        var found = self.find(key)
        if found >= 0: return found
        var handle = device.upload(mesh)
        self.keys.append(key^)
        self.handles.append(handle)
        self.bounds.append(Bounds3D(mesh.minimum,mesh.maximum))
        return len(self.keys)-1

    def load(mut self, device: Graphics3D, path: String) raises -> Int:
        var found = self.find(path)
        if found >= 0: return found
        var mesh = load_obj(path)
        return self.add(device,path,mesh)

    def validate(self, scene: Scene3D) raises:
        for node in scene.nodes:
            if node.active and (node.mesh < -1 or node.mesh >= len(self.handles)): raise Error("Scene references unknown mesh asset")

    def draw(self, device: Graphics3D, scene: Scene3D, origin: Vec3, view_projection: Mat4, shadow: Bool = False) raises:
        self.validate(scene)
        var frustum = Frustum(view_projection)
        for i in range(len(scene.nodes)):
            if not scene.valid(i): continue
            var mesh = scene.nodes[i].mesh
            if mesh < 0: continue
            var matrix = scene.world_matrix(i)
            if not frustum.visible(self.bounds[mesh].transformed(matrix),origin): continue
            if shadow: device.shadow(self.handles[mesh],matrix,origin)
            else: device.draw(self.handles[mesh],matrix,scene.nodes[i].material,origin)

    def pick(self, scene: Scene3D, origin: Vec3, direction: Vec3, maximum: Float64 = 10000) raises -> Int:
        self.validate(scene)
        var nearest = maximum
        var selected = -1
        for i in range(len(scene.nodes)):
            if not scene.valid(i): continue
            var mesh = scene.nodes[i].mesh
            if mesh < 0: continue
            var distance = self.bounds[mesh].transformed(scene.world_matrix(i)).ray(origin,direction.unit(),nearest)
            if distance >= 0 and distance <= nearest:
                selected = i
                nearest = distance
        return selected

    def close(mut self, device: Graphics3D) raises:
        for handle in self.handles: device.release(handle)
        self.keys.clear()
        self.handles.clear()
        self.bounds.clear()
