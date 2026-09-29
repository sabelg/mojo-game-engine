"""Double-precision scene graph and versioned text serialization.

Node indices are stable (tombstones on deletion). Reparenting preserves local
transforms. Mesh IDs refer to the application's asset table, not GPU handles.
"""
from .math3d import Vec3
from std.ffi import external_call
from std.math import isfinite
from .transform3d import Transform3D, Quaternion, Mat4

struct Material(ImplicitlyCopyable, Movable):
    var color: Vec3
    var roughness: Float64
    var metallic: Float64
    var emission: Float64
    var texture: Int

    def __init__(out self, color: Vec3 = Vec3(0.7, 0.7, 0.7), roughness: Float64 = 0.6, metallic: Float64 = 0, emission: Float64 = 0, texture: Int = -1):
        self.color = color
        self.roughness = max(0.045, min(1.0, roughness))
        self.metallic = max(0.0, min(1.0, metallic))
        self.emission = max(0.0, emission)
        self.texture = texture

struct SceneNode(Copyable, Movable):
    var name: String
    var parent: Int
    var transform: Transform3D
    var mesh: Int
    var material: Material
    var active: Bool

    def __init__(out self, var name: String, transform: Transform3D = Transform3D(), mesh: Int = -1, material: Material = Material(), parent: Int = -1):
        self.name = name^
        self.parent = parent
        self.transform = transform
        self.mesh = mesh
        self.material = material
        self.active = True

struct Scene3D(Copyable, Movable):
    var nodes: List[SceneNode]

    def __init__(out self):
        self.nodes = List[SceneNode]()

    def valid(self, node: Int) -> Bool:
        return node >= 0 and node < len(self.nodes) and self.nodes[node].active

    def add(mut self, var node: SceneNode) raises -> Int:
        if node.parent != -1 and not self.valid(node.parent): raise Error("Invalid scene parent")
        var index = len(self.nodes)
        self.nodes.append(node^)
        return index

    def reparent(mut self, node: Int, parent: Int) raises:
        if not self.valid(node) or (parent != -1 and not self.valid(parent)): raise Error("Invalid scene node")
        var ancestor = parent
        var visited = 0
        while ancestor != -1:
            if not self.valid(ancestor) or visited >= len(self.nodes): raise Error("Invalid scene hierarchy")
            visited += 1
            if ancestor == node: raise Error("Scene hierarchy cycle")
            ancestor = self.nodes[ancestor].parent
        self.nodes[node].parent = parent

    def world_matrix(self, node: Int) raises -> Mat4:
        if not self.valid(node): raise Error("Invalid scene node")
        var result = self.nodes[node].transform.matrix()
        var parent = self.nodes[node].parent
        var visited = 0
        while parent != -1:
            if not self.valid(parent) or visited >= len(self.nodes): raise Error("Invalid scene hierarchy")
            result = self.nodes[parent].transform.matrix()*result
            parent = self.nodes[parent].parent
            visited += 1
        return result

    def remove(mut self, node: Int) raises:
        if not self.valid(node): raise Error("Invalid scene node")
        # Find descendants before changing any active flags.
        var removed = List[Int]()
        for i in range(len(self.nodes)):
            if not self.valid(i): continue
            var ancestor = i
            var visited = 0
            while ancestor != -1:
                if not self.valid(ancestor) or visited >= len(self.nodes): raise Error("Invalid scene hierarchy")
                visited += 1
                if ancestor == node:
                    removed.append(i)
                    break
                ancestor = self.nodes[ancestor].parent
        for i in removed: self.nodes[i].active = False

    def encode(self) raises -> String:
        var result = String("MOJO_SCENE_1\n")
        for i in range(len(self.nodes)):
            var n = self.nodes[i].copy()
            if "\t" in n.name or "\n" in n.name: raise Error("Scene names cannot contain tabs/newlines")
            var t = n.transform
            var m = n.material
            result += String(i)+"\t"+n.name+"\t"+String(n.parent)+"\t"+String(n.mesh)+"\t"+String(Int(n.active))
            result += "\t"+String(t.position.x)+"\t"+String(t.position.y)+"\t"+String(t.position.z)
            result += "\t"+String(t.rotation.x)+"\t"+String(t.rotation.y)+"\t"+String(t.rotation.z)+"\t"+String(t.rotation.w)
            result += "\t"+String(t.scale.x)+"\t"+String(t.scale.y)+"\t"+String(t.scale.z)
            result += "\t"+String(m.color.x)+"\t"+String(m.color.y)+"\t"+String(m.color.z)
            result += "\t"+String(m.roughness)+"\t"+String(m.metallic)+"\t"+String(m.emission)+"\t"+String(m.texture)+"\n"
        return result^

    @staticmethod
    def decode(source: String) raises -> Self:
        var lines = source.split("\n")
        if len(lines) == 0 or String(lines[0]) != "MOJO_SCENE_1": raise Error("Unsupported scene format")
        var scene = Self()
        for i in range(1, len(lines)):
            if lines[i].byte_length() == 0: continue
            var f = String(lines[i]).split("\t")
            if len(f) != 22: raise Error("Invalid scene record")
            if Int(String(f[0])) != len(scene.nodes): raise Error("Noncontiguous scene ID")
            for field in range(5,21):
                if not isfinite(Float64(String(f[field]))): raise Error("Non-finite scene value")
            var transform = Transform3D(Vec3(Float64(String(f[5])),Float64(String(f[6])),Float64(String(f[7]))),
                Quaternion(Float64(String(f[8])),Float64(String(f[9])),Float64(String(f[10])),Float64(String(f[11]))),
                Vec3(Float64(String(f[12])),Float64(String(f[13])),Float64(String(f[14]))))
            if abs(transform.scale.x*transform.scale.y*transform.scale.z) < 1e-12: raise Error("Singular scene transform")
            var material = Material(Vec3(Float64(String(f[15])),Float64(String(f[16])),Float64(String(f[17]))),
                Float64(String(f[18])),Float64(String(f[19])),Float64(String(f[20])),Int(String(f[21])))
            var node = SceneNode(String(f[1]), transform, Int(String(f[3])), material, Int(String(f[2])))
            var active = Int(String(f[4]))
            if active != 0 and active != 1: raise Error("Invalid scene active flag")
            node.active = active == 1
            scene.nodes.append(node^)
        for i in range(len(scene.nodes)):
            if scene.valid(i): _ = scene.world_matrix(i)
        return scene^

    def save(self, var path: String) raises:
        var content = self.encode()
        var temporary = path+".tmp"
        with open(temporary, "w") as file: file.write(content)
        if external_call["rename",Int32](temporary.as_c_string_span(),path.as_c_string_span()) != 0:
            _ = external_call["remove",Int32](temporary.as_c_string_span())
            raise Error("Could not atomically replace scene file")

    @staticmethod
    def load(path: String) raises -> Self:
        with open(path, "r") as file: return Self.decode(file.read())
