"""Double-precision scene graph and versioned text serialization.

Node indices are stable (tombstones on deletion). Reparenting preserves local
transforms. Mesh IDs refer to the application's asset table, not GPU handles.
"""
from .math3d import Vec3
from std.ffi import external_call
from std.math import isfinite
from .transform3d import Transform3D, Quaternion, Mat4
from .durableio import object_id,atomic_write,read_bounded,checksum
from std.collections import Dict
from .assetio import BinaryAsset,ASSET_SCENE

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
    var asset_key: String
    var material_key: String
    var persistent_id: String

    def __init__(out self, var name: String, transform: Transform3D = Transform3D(), mesh: Int = -1, material: Material = Material(), parent: Int = -1, var asset_key: String="", var material_key: String="",var persistent_id: String=""):
        self.name = name^
        self.parent = parent
        self.transform = transform
        self.mesh = mesh
        self.material = material
        self.active = True
        self.asset_key=asset_key^
        self.material_key=material_key^
        self.persistent_id=persistent_id^

struct Scene3D(Copyable, Movable):
    var nodes: List[SceneNode]

    def __init__(out self):
        self.nodes = List[SceneNode]()

    def valid(self, node: Int) -> Bool:
        return node >= 0 and node < len(self.nodes) and self.nodes[node].active

    def add(mut self, var node: SceneNode) raises -> Int:
        if len(self.nodes)>=100000:raise Error("Scene exceeds node budget")
        if node.parent != -1 and not self.valid(node.parent): raise Error("Invalid scene parent")
        if node.persistent_id.byte_length()==0:node.persistent_id=object_id()
        for other in self.nodes:
            if other.active and node.active and other.persistent_id==node.persistent_id:raise Error("Duplicate persistent object identity")
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

    def validate_overrides(self,overrides: Dict[Int,Transform3D]) raises:
        if len(overrides)>128:raise Error("Render overrides exceed selection budget")
        for node in overrides:
            if not self.valid(node):raise Error("Render override targets an inactive node")
            var transform=overrides[node]
            for value in transform.matrix().data:
                if not isfinite(value):raise Error("Render override contains a non-finite transform")

    def world_matrix(self, node: Int,overrides: Dict[Int,Transform3D]=Dict[Int,Transform3D]()) raises -> Mat4:
        if not self.valid(node): raise Error("Invalid scene node")
        self.validate_overrides(overrides)
        var result = overrides[node].matrix() if node in overrides else self.nodes[node].transform.matrix()
        var parent = self.nodes[node].parent
        var visited = 0
        while parent != -1:
            if not self.valid(parent) or visited >= len(self.nodes): raise Error("Invalid scene hierarchy")
            result = (overrides[parent].matrix() if parent in overrides else self.nodes[parent].transform.matrix())*result
            parent = self.nodes[parent].parent
            visited += 1
        return result

    def world_matrices(self,overrides: Dict[Int,Transform3D]=Dict[Int,Transform3D]()) raises -> List[Mat4]:
        """Evaluate each transform once, without recursion or assuming parent order."""
        self.validate_overrides(overrides)
        var matrices=List[Mat4]()
        var states=List[Int]()
        for _ in self.nodes:
            matrices.append(Mat4())
            states.append(0)
        for node in range(len(self.nodes)):
            if not self.valid(node) or states[node]==2:continue
            var chain=List[Int]()
            var current=node
            while current!=-1 and states[current]!=2:
                if not self.valid(current) or states[current]==1:raise Error("Invalid scene hierarchy")
                states[current]=1
                chain.append(current)
                current=self.nodes[current].parent
                if current < -1 or current>=len(self.nodes):raise Error("Invalid scene parent")
            while len(chain)>0:
                var index=chain.pop()
                matrices[index]=overrides[index].matrix() if index in overrides else self.nodes[index].transform.matrix()
                var parent=self.nodes[index].parent
                if parent!=-1:matrices[index]=matrices[parent]*matrices[index]
                states[index]=2
        return matrices^

    def descendants(self,node: Int,limit: Int=100000) raises -> List[Int]:
        if not self.valid(node) or limit<1 or limit>100000:raise Error("Invalid scene subtree")
        _=self.world_matrices()
        var children=Dict[Int,List[Int]]()
        for i in range(len(self.nodes)):
            if not self.valid(i) or self.nodes[i].parent<0:continue
            var parent=self.nodes[i].parent
            if parent not in children:children[parent]=List[Int]()
            children[parent].append(i)
        var result=List[Int]()
        result.append(node)
        var cursor=0
        while cursor<len(result):
            var current=result[cursor]
            cursor+=1
            if current not in children:continue
            for child in children[current]:
                if len(result)>=limit:raise Error("Scene subtree exceeds authoring budget")
                result.append(child)
        return result^

    def remove(mut self,node: Int) raises:
        var removed=self.descendants(node)
        for i in removed:self.nodes[i].active=False

    def compact(mut self) raises -> List[Int]:
        """Explicitly discard tombstones; return old-to-new indices, preserving IDs.

        Callers must remap selections and discard/remap index-based undo history.
        Ordinary remove() still preserves indices until this explicit operation.
        """
        _=self.world_matrices()
        var mapping=List[Int]()
        var kept=List[SceneNode]()
        for node in self.nodes:
            mapping.append(len(kept) if node.active else -1)
            if node.active:kept.append(node.copy())
        for i in range(len(kept)):
            if kept[i].parent>=0:kept[i].parent=mapping[kept[i].parent]
        self.nodes=kept^
        return mapping^

    def encode(self) raises -> String:
        if len(self.nodes)>100000:raise Error("Scene exceeds node budget")
        _=self.world_matrices()
        var bytes=16
        for node in self.nodes:
            bytes+=512+node.name.byte_length()+node.asset_key.byte_length()+node.material_key.byte_length()+node.persistent_id.byte_length()
            if bytes>64*1024*1024:raise Error("Scene exceeds serialization byte budget")
        var result = String("MOJO_SCENE_3\n")
        var identities=Dict[String,Bool]()
        for i in range(len(self.nodes)):
            var n = self.nodes[i].copy()
            if n.active:
                if n.persistent_id.byte_length()==0 or n.persistent_id in identities:raise Error("Missing or duplicate persistent object identity")
                identities[n.persistent_id]=True
            if "\t" in n.name or "\n" in n.name: raise Error("Scene names cannot contain tabs/newlines")
            for key in [n.asset_key,n.material_key,n.persistent_id]:
                if "\t" in key or "\n" in key:raise Error("Asset IDs cannot contain tabs/newlines")
            var t = n.transform
            var m = n.material
            result += String(i)+"\t"+n.name+"\t"+String(n.parent)+"\t"+String(n.mesh)+"\t"+String(Int(n.active))
            result += "\t"+String(t.position.x)+"\t"+String(t.position.y)+"\t"+String(t.position.z)
            result += "\t"+String(t.rotation.x)+"\t"+String(t.rotation.y)+"\t"+String(t.rotation.z)+"\t"+String(t.rotation.w)
            result += "\t"+String(t.scale.x)+"\t"+String(t.scale.y)+"\t"+String(t.scale.z)
            result += "\t"+String(m.color.x)+"\t"+String(m.color.y)+"\t"+String(m.color.z)
            result += "\t"+String(m.roughness)+"\t"+String(m.metallic)+"\t"+String(m.emission)+"\t"+String(m.texture)+"\t"+n.asset_key+"\t"+n.material_key+"\t"+n.persistent_id+"\n"
        return result^

    @staticmethod
    def decode(source: String) raises -> Self:
        var lines = source.split("\n")
        if len(lines) == 0 or (String(lines[0]) != "MOJO_SCENE_1" and String(lines[0]) != "MOJO_SCENE_2" and String(lines[0])!="MOJO_SCENE_3"): raise Error("Unsupported scene format")
        var version3=String(lines[0])=="MOJO_SCENE_3"
        var version2=version3 or String(lines[0])=="MOJO_SCENE_2"
        var identities=Dict[String,Bool]()
        var scene = Self()
        var legacy_id=String(checksum(source)) if not version3 else String()
        for i in range(1, len(lines)):
            if lines[i].byte_length() == 0: continue
            if len(scene.nodes)>=100000:raise Error("Scene exceeds node budget")
            var f = String(lines[i]).split("\t")
            if len(f) != (25 if version3 else (24 if version2 else 22)): raise Error("Invalid scene record")
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
            if version2:
                node.asset_key=String(f[22])
                node.material_key=String(f[23])
            var active = Int(String(f[4]))
            if active != 0 and active != 1: raise Error("Invalid scene active flag")
            node.active = active == 1
            node.persistent_id=String(f[24]) if version3 else "legacy:"+legacy_id+":"+String(i)
            if node.active:
                if node.persistent_id.byte_length()==0:raise Error("Missing persistent object identity")
                if node.persistent_id in identities:raise Error("Duplicate persistent object identity")
                identities[node.persistent_id]=True
            scene.nodes.append(node^)
        _=scene.world_matrices()
        return scene^

    def save(self, var path: String) raises:
        atomic_write(path,self.encode())

    @staticmethod
    def load(path: String) raises -> Self:
        if path.endswith(".sceneb"):
            var source=BinaryAsset(path,ASSET_SCENE)
            var scene=Self()
            var count=source.count(100000)
            var ids=Dict[String,Bool]()
            for _ in range(count):
                var name=source.identifier()
                var parent=source.integer()
                var mesh=source.integer()
                var active=source.uint(4)
                if active>1:raise Error("Invalid binary scene active flag")
                var values=List[Float64]()
                for _ in range(16):values.append(source.floating())
                if abs(values[7]*values[8]*values[9])<1e-12:raise Error("Singular binary scene transform")
                var texture=source.integer()
                var asset=source.identifier()
                var material=source.identifier()
                var identity=source.identifier()
                var node=SceneNode(name^,Transform3D(Vec3(values[0],values[1],values[2]),Quaternion(values[3],values[4],values[5],values[6]),Vec3(values[7],values[8],values[9])),mesh,Material(Vec3(values[10],values[11],values[12]),values[13],values[14],values[15],texture),parent,asset^,material^,identity^)
                node.active=active==1
                if node.active:
                    if node.persistent_id.byte_length()==0 or node.persistent_id in ids:raise Error("Missing or duplicate binary scene identity")
                    ids[node.persistent_id]=True
                scene.nodes.append(node^)
            source.finish()
            _=scene.world_matrices()
            return scene^
        return Self.decode(read_bounded(path))
