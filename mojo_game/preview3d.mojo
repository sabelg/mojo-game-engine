"""Bounded, read-only transform previews; authored scenes remain saveable."""
from std.collections import Dict
from std.math import isfinite,round
from .partition import WorldPartition
from .scene3d import Scene3D
from .transform3d import Mat4,Transform3D,Quaternion
from .math3d import Vec3

@fieldwise_init
struct ObjectSelection(ImplicitlyCopyable,Movable):
    var x: Int
    var z: Int
    var node: Int

def preview_matrix(scene: Scene3D,node: Int) raises -> Mat4:
    var ancestor=node
    var depth=0
    while ancestor!=-1:
        if not scene.valid(ancestor) or depth>=256:raise Error("Transform preview hierarchy exceeds depth 256 or is invalid")
        depth+=1
        ancestor=scene.nodes[ancestor].parent
    return scene.world_matrix(node)

def same_transform(a: Transform3D,b: Transform3D) -> Bool:
    return a.position.x==b.position.x and a.position.y==b.position.y and a.position.z==b.position.z and a.rotation.x==b.rotation.x and a.rotation.y==b.rotation.y and a.rotation.z==b.rotation.z and a.rotation.w==b.rotation.w and a.scale.x==b.scale.x and a.scale.y==b.scale.y and a.scale.z==b.scale.z

@fieldwise_init
struct PreviewItem3D(Copyable,Movable):
    var address: ObjectSelection
    var identity: String
    var parent: Int
    var before: Transform3D
    var after: Transform3D
    var parent_inverse: Mat4
    var world_before: Mat4

struct TransformPreview3D(Copyable,Movable):
    var items: List[PreviewItem3D]

    def __init__(out self):
        self.items=List[PreviewItem3D]()

    @staticmethod
    def capture(world: WorldPartition,selection: List[ObjectSelection]) raises -> TransformPreview3D:
        if len(selection)<1 or len(selection)>128:raise Error("Transform preview needs 1..128 selected objects")
        var result=TransformPreview3D()
        # Validate every selected address before filtering descendants/duplicates.
        for item in selection:
            var cell=world.find(item.x,item.z)
            if cell<0 or not world.cells[cell].scene.valid(item.node):raise Error("Selected object is no longer resident")
            _=preview_matrix(world.cells[cell].scene,item.node)
        for item in selection:
            var cell=world.find(item.x,item.z)
            ref scene=world.cells[cell].scene
            var ancestor=scene.nodes[item.node].parent
            var covered=False
            while ancestor>=0:
                for other in selection:
                    if other.x==item.x and other.z==item.z and other.node==ancestor:covered=True
                ancestor=scene.nodes[ancestor].parent
            for prior in result.items:
                if prior.address.x==item.x and prior.address.z==item.z and prior.address.node==item.node:covered=True
            if covered:continue
            var identity=scene.nodes[item.node].persistent_id.copy()
            if identity.byte_length()<1 or identity.byte_length()>64:raise Error("Invalid preview object identity")
            var parent=scene.nodes[item.node].parent
            var inverse=preview_matrix(scene,parent).inverse() if parent>=0 else Mat4()
            var before=scene.nodes[item.node].transform
            var matrix=preview_matrix(scene,item.node)
            for value in matrix.data:
                if not isfinite(value):raise Error("Non-finite preview transform")
            result.items.append(PreviewItem3D(item,identity^,parent,before,before,inverse^,matrix^))
        return result^

    def validate(self,world: WorldPartition) raises:
        if len(self.items)<1 or len(self.items)>128:raise Error("Invalid transform preview")
        for item in self.items:
            var cell=world.find(item.address.x,item.address.z)
            if cell<0 or not world.cells[cell].scene.valid(item.address.node):raise Error("Preview object was unloaded or removed")
            ref node=world.cells[cell].scene.nodes[item.address.node]
            if node.persistent_id!=item.identity or node.parent!=item.parent or not same_transform(node.transform,item.before):raise Error("Preview object changed; start a new gesture")
            var matrix=preview_matrix(world.cells[cell].scene,item.address.node)
            for i in range(16):
                if matrix.data[i]!=item.world_before.data[i]:raise Error("Preview hierarchy changed; start a new gesture")

    def update(mut self,delta: Vec3=Vec3(0,0,0),axis: Vec3=Vec3(0,1,0),angle: Float64=0,scale: Vec3=Vec3(1,1,1),local: Bool=False,snap: Float64=0) raises:
        for value in [delta.x,delta.y,delta.z,axis.x,axis.y,axis.z,angle,scale.x,scale.y,scale.z,snap]:
            if not isfinite(value):raise Error("Non-finite transform preview")
        if min(scale.x,min(scale.y,scale.z))<=0 or max(scale.x,max(scale.y,scale.z))>100 or snap<0 or snap>100 or (angle!=0 and (not isfinite(axis.length()) or axis.length()<1e-8)):raise Error("Invalid transform preview parameters")
        var candidates=List[Transform3D]()
        for item in self.items:
            var after=item.before
            var displacement=after.rotation.rotate(delta) if local else item.parent_inverse.direction(delta)
            after.position=after.position+displacement
            if snap>0:
                var position=after.position if local else item.world_before.point(Vec3(0,0,0))+delta
                position=Vec3(round(position.x/snap)*snap,round(position.y/snap)*snap,round(position.z/snap)*snap)
                after.position=position if local else item.parent_inverse.point(position)
            var rotation_axis=axis if local else item.parent_inverse.direction(axis).unit()
            var rotation=Quaternion.axis_angle(rotation_axis,angle)
            after.rotation=(after.rotation*rotation if local else rotation*after.rotation).normalized()
            after.scale=Vec3(after.scale.x*scale.x,after.scale.y*scale.y,after.scale.z*scale.z)
            if min(abs(after.scale.x),min(abs(after.scale.y),abs(after.scale.z)))<.0001:raise Error("Preview scale is too small")
            for value in after.matrix().data:
                if not isfinite(value):raise Error("Preview transform overflow")
            candidates.append(after)
        for i in range(len(self.items)):self.items[i].after=candidates[i]

    def overrides(self,x: Int,z: Int) -> Dict[Int,Transform3D]:
        var result=Dict[Int,Transform3D]()
        for item in self.items:
            if item.address.x==x and item.address.z==z:result[item.address.node]=item.after
        return result^
