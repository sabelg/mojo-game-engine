"""Partition authoring with delta undo, stable cell/node selection and transfers."""
from .partition import WorldPartition
from .scene3d import SceneNode,Scene3D
from .math3d import Vec3
from .transform3d import Transform3D,Quaternion
from .scene3d import Material
from std.math import isfinite,round
from .durableio import object_id
from .terrainlayer import TerrainChange
from .preview3d import ObjectSelection,TransformPreview3D

struct NodeChange(Copyable,Movable):
    var x: Int
    var z: Int
    var node: Int
    var before: SceneNode
    var after: SceneNode
    def __init__(out self,x: Int,z: Int,node: Int,var before: SceneNode,var after: SceneNode):
        self.x=x
        self.z=z
        self.node=node
        self.before=before^
        self.after=after^
struct WorldEdit(Copyable,Movable):
    var changes: List[NodeChange]
    var terrain: List[TerrainChange]
    def __init__(out self):
        self.changes=List[NodeChange]()
        self.terrain=List[TerrainChange]()

struct WorldEditor:
    var x: Int
    var z: Int
    var selected: Int
    var undo_stack: List[WorldEdit]
    var redo_stack: List[WorldEdit]
    var status: String
    var selection: List[ObjectSelection]
    var grouping: Bool
    var group: WorldEdit
    def __init__(out self):
        self.x=0
        self.z=0
        self.selected=-1
        self.undo_stack=List[WorldEdit]()
        self.redo_stack=List[WorldEdit]()
        self.status=String("READY")
        self.selection=List[ObjectSelection]()
        self.grouping=False
        self.group=WorldEdit()
    def apply(self,mut world: WorldPartition,edit: WorldEdit,reverse: Bool=False) raises:
        world.prepare()
        if len(edit.changes)>16384 or len(edit.terrain)>65536 or self.grouping and len(self.group.changes)+len(edit.changes)>16384:raise Error("Authoring command exceeds delta budget")
        # Load all required cells before changing any content.
        for change in edit.changes:_=world.ensure(change.x,change.z)
        for change in edit.changes:
            var cell=world.find(change.x,change.z)
            if change.node<0 or change.node>=len(world.cells[cell].scene.nodes):raise Error("Undo references missing node")
        if len(edit.terrain)>0:
            world.terrain.apply(edit.terrain,reverse)
            world.mark_terrain_dirty()
        for i in range(len(edit.changes)):
            ref change=edit.changes[len(edit.changes)-1-i if reverse else i]
            var cell=world.find(change.x,change.z)
            world.cells[cell].scene.nodes[change.node]=change.before.copy() if reverse else change.after.copy()
            world.mark_dirty(change.x,change.z)
    def sculpt(mut self,mut world: WorldPartition,center: Vec3,radius: Float64,amount: Float64) raises:
        world.prepare()
        var edit=WorldEdit()
        edit.terrain=world.terrain.brush(center,radius,amount)
        if self.grouping and len(self.group.terrain)+len(edit.terrain)>65536:raise Error("Authoring group exceeds terrain budget")
        self.apply(world,edit)
        self.commit(edit^)
        self.status=String("TERRAIN SCULPTED")
    def paint(mut self,mut world: WorldPartition,center: Vec3,radius: Float64,color: Vec3,strength: Float64=1) raises:
        world.prepare()
        var edit=WorldEdit()
        edit.terrain=world.terrain.brush(center,radius,strength,color,True)
        if self.grouping and len(self.group.terrain)+len(edit.terrain)>65536:raise Error("Authoring group exceeds terrain budget")
        self.apply(world,edit)
        self.commit(edit^)
        self.status=String("TERRAIN PAINTED")
    def begin_group(mut self) raises:
        if self.grouping:raise Error("Authoring command group already open")
        self.group=WorldEdit()
        self.grouping=True
    def finish_group(mut self):
        self.grouping=False
        var edit=self.group^
        self.group=WorldEdit()
        self.commit(edit^)
    def cancel_group(mut self,mut world: WorldPartition) raises:
        if not self.grouping:return
        self.apply(world,self.group,True)
        self.grouping=False
        self.group=WorldEdit()
    def commit(mut self,var edit: WorldEdit):
        if self.grouping:
            for change in edit.changes:self.group.changes.append(change.copy())
            for change in edit.terrain:self.group.terrain.append(change)
            return
        if len(edit.changes)==0 and len(edit.terrain)==0:return
        if len(self.undo_stack)>=32:
            var kept=List[WorldEdit]()
            for i in range(1,len(self.undo_stack)):kept.append(self.undo_stack[i].copy())
            self.undo_stack=kept^
        self.undo_stack.append(edit^)
        self.redo_stack.clear()
    def undo(mut self,mut world: WorldPartition) raises:
        if self.grouping:raise Error("Finish the active authoring command first")
        if len(self.undo_stack)==0:return
        if len(self.undo_stack[len(self.undo_stack)-1].changes)>0:self.selection.clear()
        self.apply(world,self.undo_stack[len(self.undo_stack)-1],True)
        self.redo_stack.append(self.undo_stack.pop())
        if len(self.redo_stack[len(self.redo_stack)-1].changes)>0:self.selected=-1
        for change in self.redo_stack[len(self.redo_stack)-1].changes:
            if change.before.active:
                self.x=change.x
                self.z=change.z
                self.selected=change.node
                break
        self.status=String("UNDO")
    def redo(mut self,mut world: WorldPartition) raises:
        if self.grouping:raise Error("Finish the active authoring command first")
        if len(self.redo_stack)==0:return
        if len(self.redo_stack[len(self.redo_stack)-1].changes)>0:self.selection.clear()
        self.apply(world,self.redo_stack[len(self.redo_stack)-1])
        self.undo_stack.append(self.redo_stack.pop())
        if len(self.undo_stack[len(self.undo_stack)-1].changes)>0:self.selected=-1
        for change in self.undo_stack[len(self.undo_stack)-1].changes:
            if change.after.active:
                self.x=change.x
                self.z=change.z
                self.selected=change.node
                break
        self.status=String("REDO")
    def place(mut self,mut world: WorldPartition,var node: SceneNode) raises:
        var position=node.transform.position
        if not isfinite(position.x) or not isfinite(position.y) or not isfinite(position.z) or abs(position.x/world.cell_size)>Float64(1<<40) or abs(position.z/world.cell_size)>Float64(1<<40):raise Error("Invalid object position")
        if self.grouping and len(self.group.changes)>=16384:raise Error("Authoring group exceeds node budget")
        var x=Int(node.transform.position.x//world.cell_size)
        var z=Int(node.transform.position.z//world.cell_size)
        var cell=world.ensure(x,z)
        if node.parent!=-1:raise Error("Placed objects must be roots")
        node.persistent_id=object_id()
        var before=node.copy()
        before.active=False
        var edit=WorldEdit()
        var index=world.cells[cell].scene.add(node.copy())
        edit.changes.append(NodeChange(x,z,index,before^,node^))
        world.mark_dirty(x,z)
        self.commit(edit^)
        self.x=x
        self.z=z
        self.selected=index
        self.selection.clear()
        self.selection.append(ObjectSelection(x,z,index))
    def transform(mut self,mut world: WorldPartition,transform: Transform3D) raises:
        for value in [transform.position.x,transform.position.y,transform.position.z,transform.rotation.x,transform.rotation.y,transform.rotation.z,transform.rotation.w,transform.scale.x,transform.scale.y,transform.scale.z]:
            if not isfinite(value):raise Error("Non-finite object transform")
        if abs(transform.position.x/world.cell_size)>Float64(1<<40) or abs(transform.position.z/world.cell_size)>Float64(1<<40) or abs(transform.scale.x*transform.scale.y*transform.scale.z)<1e-12:raise Error("Invalid object transform")
        var cell=world.find(self.x,self.z)
        if cell<0 or not world.cells[cell].scene.valid(self.selected):raise Error("Select a resident object")
        var selected_x=self.x
        var selected_z=self.z
        var selected_node=self.selected
        var before=world.cells[cell].scene.nodes[self.selected].copy()
        var after=before.copy()
        after.transform=transform
        var edit=WorldEdit()
        var destination_x=Int(transform.position.x//world.cell_size)
        var destination_z=Int(transform.position.z//world.cell_size)
        if after.parent!=-1 or (destination_x==self.x and destination_z==self.z):
            edit.changes.append(NodeChange(self.x,self.z,self.selected,before^,after^))
            self.apply(world,edit)
        else:
            # Transfer a complete hierarchy, preserving child-local transforms.
            var source_x=self.x
            var source_z=self.z
            var destination=world.ensure(destination_x,destination_z)
            cell=world.find(source_x,source_z)
            var scene=world.cells[cell].scene.copy()
            var mapping=List[Int]()
            for _ in scene.nodes:mapping.append(-1)
            var included=scene.descendants(self.selected,4096)
            if len(world.cells[destination].scene.nodes)+len(included)>100000:raise Error("Hierarchy transfer exceeds cell node budget")
            if self.grouping and len(self.group.changes)+len(included)*2>16384:raise Error("Authoring group exceeds node budget")
            for i in included:
                var moved=scene.nodes[i].copy()
                if i==self.selected:moved.transform=transform
                var tombstone=moved.copy()
                tombstone.active=False
                tombstone.parent=-1
                var index=len(world.cells[destination].scene.nodes)
                world.cells[destination].scene.nodes.append(tombstone.copy())
                mapping[i]=index
                edit.changes.append(NodeChange(source_x,source_z,i,scene.nodes[i].copy(),tombstone.copy()))
                edit.changes.append(NodeChange(destination_x,destination_z,index,tombstone^,moved^))
            for i in range(1,len(edit.changes),2):
                var parent=edit.changes[i].after.parent
                if parent>=0:edit.changes[i].after.parent=mapping[parent]
            self.apply(world,edit)
            self.selected=mapping[self.selected]
            self.x=destination_x
            self.z=destination_z
        self.commit(edit^)
        for i in range(len(self.selection)):
            if self.selection[i].x==selected_x and self.selection[i].z==selected_z and self.selection[i].node==selected_node:self.selection[i]=ObjectSelection(self.x,self.z,self.selected)
        self.status=String("TRANSFORM UPDATED")
    def delete(mut self,mut world: WorldPartition) raises:
        var cell=world.find(self.x,self.z)
        if cell<0 or not world.cells[cell].scene.valid(self.selected):return
        var scene=world.cells[cell].scene.copy()
        var included=scene.descendants(self.selected,4096)
        if self.grouping and len(self.group.changes)+len(included)>16384:raise Error("Authoring group exceeds node budget")
        world.cells[cell].scene.remove(self.selected)
        var edit=WorldEdit()
        for i in range(len(scene.nodes)):
            if scene.nodes[i].active!=world.cells[cell].scene.nodes[i].active:
                edit.changes.append(NodeChange(self.x,self.z,i,scene.nodes[i].copy(),world.cells[cell].scene.nodes[i].copy()))
        world.mark_dirty(self.x,self.z)
        self.commit(edit^)

    def select(mut self,world: WorldPartition,x: Int,z: Int,node: Int,append: Bool=False) raises:
        var cell=world.find(x,z)
        if cell<0 or not world.cells[cell].scene.valid(node):raise Error("Select a resident object")
        if not append:self.selection.clear()
        for i in range(len(self.selection)):
            var selected=self.selection[i]
            if selected.x==x and selected.z==z and selected.node==node:
                if append:_=self.selection.pop(i)
                self.x=x;self.z=z;self.selected=node
                return
        if len(self.selection)>=128:raise Error("Selection exceeds object budget")
        self.selection.append(ObjectSelection(x,z,node))
        self.x=x;self.z=z;self.selected=node
    def adjust_selection(mut self,mut world: WorldPartition,delta: Vec3,axis: Vec3=Vec3(0,1,0),angle: Float64=0,factor: Float64=1,local: Bool=False,snap: Float64=0) raises:
        var candidate=self.preview(world)
        candidate.update(delta,axis,angle,Vec3(factor,factor,factor),local,snap)
        self.commit_preview(world,candidate)

    def preview(self,world: WorldPartition) raises -> TransformPreview3D:
        if self.grouping:raise Error("Finish the active command before previewing")
        var selection=self.selection.copy()
        if len(selection)==0:selection.append(ObjectSelection(self.x,self.z,self.selected))
        return TransformPreview3D.capture(world,selection)

    def commit_preview(mut self,mut world: WorldPartition,preview: TransformPreview3D) raises:
        preview.validate(world)
        var primary=ObjectSelection(self.x,self.z,self.selected)
        var selected=self.selection.copy()
        var moved=List[ObjectSelection]()
        self.begin_group()
        try:
            for item in preview.items:
                self.x=item.address.x;self.z=item.address.z;self.selected=item.address.node
                self.transform(world,item.after)
                moved.append(ObjectSelection(self.x,self.z,self.selected))
        except error:
            self.cancel_group(world)
            self.selection=selected^
            self.x=primary.x;self.z=primary.z;self.selected=primary.node
            raise error^
        self.finish_group()
        self.selection=moved^
        self.status="SELECTION TRANSFORMED"

    def delete_selection(mut self,mut world: WorldPartition) raises:
        if self.selected<0 and len(self.selection)==0:return
        var roots=self.preview(world)
        var edit=WorldEdit()
        for item in roots.items:
            var cell=world.find(item.address.x,item.address.z)
            var included=world.cells[cell].scene.descendants(item.address.node,4096)
            if len(edit.changes)+len(included)>16384:raise Error("Selection delete exceeds node budget")
            for index in included:
                var before=world.cells[cell].scene.nodes[index].copy()
                var after=before.copy()
                after.active=False
                edit.changes.append(NodeChange(item.address.x,item.address.z,index,before^,after^))
        self.apply(world,edit)
        self.commit(edit^)
        self.selection.clear()
        self.selected=-1
        self.status="SELECTION DELETED"

    def duplicate_selection(mut self,mut world: WorldPartition,offset: Vec3=Vec3(3,0,0)) raises:
        for value in [offset.x,offset.y,offset.z]:
            if not isfinite(value):raise Error("Invalid duplicate offset")
        var roots=self.preview(world)
        var edit=WorldEdit()
        var selection=List[ObjectSelection]()
        # Prepare all copies and budgets before appending any target slots.
        for item in roots.items:
            var cell=world.find(item.address.x,item.address.z)
            var included=world.cells[cell].scene.descendants(item.address.node,4096)
            if len(edit.changes)+len(included)>16384:raise Error("Selection duplicate exceeds node budget")
            var copies=List[SceneNode]()
            var mapping=List[Int](length=len(world.cells[cell].scene.nodes),fill=-1)
            for index in included:copies.append(world.cells[cell].scene.nodes[index].copy())
            var root=copies[0].transform
            root.position=root.position+item.parent_inverse.direction(offset)
            if abs(root.position.x/world.cell_size)>Float64(1<<40) or abs(root.position.z/world.cell_size)>Float64(1<<40):raise Error("Duplicate position exceeds world budget")
            var x=item.address.x if item.parent>=0 else Int(root.position.x//world.cell_size)
            var z=item.address.z if item.parent>=0 else Int(root.position.z//world.cell_size)
            var destination=world.ensure(x,z)
            var base=len(world.cells[destination].scene.nodes)
            for prior in edit.changes:
                if prior.x==x and prior.z==z:base+=1
            if base+len(copies)>100000:raise Error("Duplicate exceeds cell node budget")
            for i in range(len(included)):mapping[included[i]]=base+i
            for i in range(len(copies)):
                var after=copies[i].copy()
                after.persistent_id=object_id()
                if i==0:
                    after.transform=root
                    after.name+=" COPY"
                elif after.parent>=0:after.parent=mapping[after.parent]
                var before=after.copy()
                before.active=False;before.parent=-1
                edit.changes.append(NodeChange(x,z,base+i,before^,after^))
            selection.append(ObjectSelection(x,z,base))
        for change in edit.changes:
            var cell=world.find(change.x,change.z)
            world.cells[cell].scene.nodes.append(change.before.copy())
        self.apply(world,edit)
        self.commit(edit^)
        self.selection=selection^
        self.x=self.selection[0].x;self.z=self.selection[0].z;self.selected=self.selection[0].node
        self.status="SELECTION DUPLICATED"

    def prefab(self,world: WorldPartition) raises -> Scene3D:
        var cell=world.find(self.x,self.z)
        if cell<0:raise Error("Prefab root is not resident")
        ref source=world.cells[cell].scene
        var included=source.descendants(self.selected,4096)
        var mapping=List[Int](length=len(source.nodes),fill=-1)
        var result=Scene3D()
        for i in included:
            mapping[i]=len(result.nodes)
            result.nodes.append(source.nodes[i].copy())
        for i in range(len(result.nodes)):
            var parent=result.nodes[i].parent
            result.nodes[i].parent=mapping[parent] if parent>=0 and mapping[parent]>=0 else -1
            if i==0:result.nodes[i].transform.position=Vec3(0,0,0)
        return result^
    def instantiate(mut self,mut world: WorldPartition,prefab: Scene3D,position: Vec3) raises:
        if len(prefab.nodes)==0 or len(prefab.nodes)>4096:raise Error("Invalid prefab size")
        var source=prefab.copy()
        _=source.compact()
        if len(source.nodes)==0:raise Error("Prefab has no active nodes")
        if not isfinite(position.x) or not isfinite(position.y) or not isfinite(position.z):raise Error("Invalid prefab position")
        var x=Int(position.x//world.cell_size)
        var z=Int(position.z//world.cell_size)
        var cell=world.ensure(x,z)
        var base=len(world.cells[cell].scene.nodes)
        if self.grouping and len(self.group.changes)+len(source.nodes)>16384:raise Error("Authoring group exceeds node budget")
        if base+len(source.nodes)>100000:raise Error("Prefab exceeds cell node budget")
        var edit=WorldEdit()
        for i in range(len(source.nodes)):
            var after=source.nodes[i].copy()
            after.persistent_id=object_id()
            if after.parent<0:after.transform.position=after.transform.position+position
            else:after.parent+=base
            var before=after.copy()
            before.active=False;before.parent=-1
            world.cells[cell].scene.nodes.append(before.copy())
            edit.changes.append(NodeChange(x,z,base+i,before^,after^))
        self.apply(world,edit)
        self.commit(edit^)
        self.select(world,x,z,base)
        self.status="PREFAB PLACED"
    def material(mut self,mut world: WorldPartition,material: Material) raises:
        for value in [material.color.x,material.color.y,material.color.z,material.roughness,material.metallic,material.emission]:
            if not isfinite(value):raise Error("Non-finite material property")
        var cell=world.find(self.x,self.z)
        if cell<0 or not world.cells[cell].scene.valid(self.selected):raise Error("Select a resident object")
        var before=world.cells[cell].scene.nodes[self.selected].copy()
        var after=before.copy()
        after.material=material;after.material_key=String()
        var edit=WorldEdit()
        edit.changes.append(NodeChange(self.x,self.z,self.selected,before^,after^))
        self.apply(world,edit);self.commit(edit^)
