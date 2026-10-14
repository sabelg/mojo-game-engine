"""Explicit cell-collider ownership and safe revision replacement.

Build a cell completely before publication. Failure retains its previous
collision. Eviction frees geometry and invalidates generational support handles.
Call ready() before allowing a character into a streamed cell.
"""
from .partition import WorldPartition
from .assets3d import Assets3D
from .character3d import CollisionWorld3D
from .triangle3d import TriangleMesh3D
from std.collections import Dict
from .streaming import StreamQueue,StreamJob,StreamScheduler,COLLISION_JOB
from .terrain import TerrainConfig

struct CollisionCell(Copyable,Movable):
    var x: Int
    var z: Int
    var revision: Int
    var asset_revision: UInt64
    var handles: List[Int]
    def __init__(out self,x: Int,z: Int,revision: Int,asset_revision: UInt64):
        self.x=x
        self.z=z
        self.revision=revision
        self.asset_revision=asset_revision
        self.handles=List[Int]()

struct CollisionStreamer3D:
    var cells: List[CollisionCell]
    var budget: Int
    var byte_budget: Int
    var asynchronous: Bool
    var queue: StreamQueue
    var signature: String
    def __init__(out self,budget: Int=1,byte_budget: Int=64*1024*1024,asynchronous: Bool=False,scheduler: Optional[StreamScheduler]=None) raises:
        if budget<1 or budget>64:raise Error("Invalid collision streaming budget")
        self.cells=List[CollisionCell]()
        self.budget=budget
        if byte_budget<4096:raise Error("Invalid collision payload budget")
        self.byte_budget=byte_budget
        self.asynchronous=asynchronous
        self.queue=StreamQueue(scheduler=scheduler)
        self.signature=String()
    def find(self,x: Int,z: Int) -> Int:
        for i in range(len(self.cells)):
            if self.cells[i].x==x and self.cells[i].z==z:return i
        return -1
    def ready(self,world: WorldPartition,assets: Assets3D,x: Int,z: Int) -> Bool:
        var scene=world.find(x,z)
        var collision=self.find(x,z)
        return scene>=0 and collision>=0 and self.cells[collision].revision==world.cells[scene].revision and self.cells[collision].asset_revision==assets.revision
    def resident_bytes(self,collision: CollisionWorld3D) -> Int:
        var total=0
        for cell in self.cells:
            for handle in cell.handles:total+=collision.meshes[(-handle-2)&1048575].payload_bytes()
        return total
    def update(mut self,world: WorldPartition,assets: Assets3D,mut collision: CollisionWorld3D) raises:
        var kept=List[CollisionCell]()
        for cell in self.cells:
            if world.find(cell.x,cell.z)<0:
                for handle in cell.handles:collision.remove_mesh(handle)
            else:kept.append(cell.copy())
        self.cells=kept^
        if self.asynchronous:
            self.update_async(world,assets,collision)
            return
        var remaining=self.budget
        for cell in world.cells:
            if self.ready(world,assets,cell.x,cell.z):continue
            if remaining==0:break
            var prepared=List[TriangleMesh3D]()
            var prepared_bytes=0
            var matrices=cell.scene.world_matrices()
            assets.validate(cell.scene)
            for i in range(len(cell.scene.nodes)):
                if not cell.scene.valid(i):continue
                var mesh=assets.node_mesh(cell.scene,i)
                if mesh<0:continue
                var key=assets.keys[mesh].copy()
                # Availability of a cooked collider is an explicit import policy.
                # Render-only assets intentionally need no collision record.
                if key in assets.collision_paths:
                    var collider=assets.collider(key,matrices[i],self.byte_budget-prepared_bytes)
                    prepared_bytes+=collider.payload_bytes()
                    prepared.append(collider^)
            self.publish(cell.x,cell.z,cell.revision,assets.revision,prepared^,collision)
            remaining-=1
    def publish(mut self,x: Int,z: Int,revision: Int,asset_revision: UInt64,var prepared: List[TriangleMesh3D],mut collision: CollisionWorld3D) raises:
        var prepared_bytes=0
        for collider in prepared:prepared_bytes+=collider.payload_bytes()
        var found=self.find(x,z)
        var previous_bytes=0
        if found>=0:
            for handle in self.cells[found].handles:previous_bytes+=collision.meshes[(-handle-2)&1048575].payload_bytes()
        if self.resident_bytes(collision)-previous_bytes+prepared_bytes>self.byte_budget:raise Error("Resident collision exceeds payload budget")
        var replacement=CollisionCell(x,z,revision,asset_revision)
        try:
            while len(prepared)>0:replacement.handles.append(collision.add_collider(prepared.pop()))
        except error:
            for handle in replacement.handles:collision.remove_mesh(handle)
            raise error^
        if found>=0:
            for handle in self.cells[found].handles:collision.remove_mesh(handle)
            self.cells[found]=replacement^
        else:self.cells.append(replacement^)
    def update_async(mut self,world: WorldPartition,assets: Assets3D,mut collision: CollisionWorld3D) raises:
        var signature=String(assets.revision)
        for cell in world.cells:signature+="/"+String(cell.x)+":"+String(cell.z)+":"+String(cell.revision)
        if signature!=self.signature:
            self.queue.invalidate()
            self.signature=signature^
        for _ in range(self.budget):
            var result=self.queue.take()
            if not result:break
            var job=result.value().copy()
            var found=world.find(job.x,job.z)
            if found<0 or world.cells[found].revision!=job.revision or job.asset_revision!=assets.revision:continue
            if job.error.byte_length()>0:raise Error(job.error)
            var prepared=job.colliders^
            job.colliders=List[TriangleMesh3D]()
            self.publish(job.x,job.z,job.revision,job.asset_revision,prepared^,collision)
        var submitted=0
        for cell in world.cells:
            if self.ready(world,assets,cell.x,cell.z):continue
            if submitted>=self.budget:break
            assets.validate(cell.scene)
            var matrices=cell.scene.world_matrices()
            var job=StreamJob("collision:"+String(cell.x)+":"+String(cell.z)+":"+String(cell.revision)+":"+String(assets.revision),COLLISION_JOB,TerrainConfig(),cell.x,cell.z)
            job.revision=cell.revision
            job.asset_revision=assets.revision
            for i in range(len(cell.scene.nodes)):
                if not cell.scene.valid(i):continue
                var mesh=assets.node_mesh(cell.scene,i)
                if mesh<0:continue
                var key=assets.keys[mesh].copy()
                if key in assets.collision_paths:
                    if len(job.collision_paths)>=256:raise Error("Cell exceeds collision instance budget")
                    job.collision_paths.append(assets.collision_paths[key].copy())
                    job.collision_matrices.append(matrices[i])
            if len(job.collision_paths)==0:self.publish(cell.x,cell.z,cell.revision,assets.revision,List[TriangleMesh3D](),collision)
            elif self.queue.submit(job^):submitted+=1
    def clear(mut self,mut collision: CollisionWorld3D) raises:
        self.queue.close()
        for cell in self.cells:
            for handle in cell.handles:collision.remove_mesh(handle)
        self.cells.clear()
