"""Budgeted, disk-backed world cells for authored scene content.

Cell files contain world-space root transforms. The caller owns the directory
and stable asset table. Edits must be marked dirty; dirty cells are saved before
eviction. Loading errors propagate instead of silently discarding content.
"""
from std.ffi import external_call
from .math3d import Vec3
from .scene3d import Scene3D
from .terrain import TerrainConfig
from .terrainlayer import TerrainLayer,TERRAIN_CELL
from .durableio import exists
from .streaming import StreamQueue,StreamJob,LOAD_CELL_JOB,SAVE_WORLD_JOB,StreamScheduler
from .worldstore import WorldStore,CellSnapshot
from .visibility3d import SceneDrawCache
from std.collections import Dict

struct WorldCell(Copyable, Movable):
    var x: Int
    var z: Int
    var scene: Scene3D
    var dirty: Bool
    var revision: Int
    var render_cache: SceneDrawCache

    def __init__(out self, x: Int, z: Int, var scene: Scene3D):
        # Identical legacy scene payloads in different cells describe distinct
        # objects. Namespace migrated IDs once; version-3 identities stay intact.
        for i in range(len(scene.nodes)):
            if scene.nodes[i].persistent_id.startswith("legacy:"):
                scene.nodes[i].persistent_id="cell:"+String(x)+":"+String(z)+":"+scene.nodes[i].persistent_id
        self.x = x
        self.z = z
        self.scene = scene^
        self.dirty = False
        self.revision=0
        self.render_cache=SceneDrawCache()

struct WorldPartition:
    var directory: String
    var cell_size: Float64
    var radius: Int
    var budget: Int
    var cells: List[WorldCell]
    var asynchronous: Bool
    var queue: StreamQueue
    var saves: Dict[String,Int]
    var store: WorldStore
    var terrain: TerrainLayer
    var terrain_loaded: Bool
    var terrain_dirty: Bool
    var terrain_revision: Int

    def __init__(out self, var directory: String, cell_size: Float64 = 256, radius: Int = 1, budget: Int = 2, asynchronous: Bool=False,scheduler: Optional[StreamScheduler]=None) raises:
        if cell_size <= 0 or radius < 0 or radius > 16 or budget < 1: raise Error("Invalid world partition configuration")
        self.directory = directory^
        self.cell_size = cell_size
        self.radius = radius
        self.budget = budget
        self.cells = List[WorldCell]()
        self.asynchronous=asynchronous
        self.queue=StreamQueue(scheduler=scheduler,serial=True)
        self.saves=Dict[String,Int]()
        self.store=WorldStore(self.directory.copy())
        self.terrain=TerrainLayer()
        self.terrain_loaded=False
        self.terrain_dirty=False
        self.terrain_revision=1

    def prepare(mut self) raises:
        self.store.prepare()
        if not self.terrain_loaded:
            var path=self.path(TERRAIN_CELL,TERRAIN_CELL)
            if exists(path):self.terrain=TerrainLayer.from_scene(Scene3D.load(path))
            self.terrain_loaded=True

    def mark_terrain_dirty(mut self):
        self.terrain_dirty=True
        self.terrain_revision+=1

    def path(self, x: Int, z: Int) -> String:
        return self.directory+"/cell_"+String(x)+"_"+String(z)+".scene"

    def find(self, x: Int, z: Int) -> Int:
        for i in range(len(self.cells)):
            if self.cells[i].x == x and self.cells[i].z == z: return i
        return -1

    def mark_dirty(mut self, x: Int, z: Int) raises:
        var i = self.find(x,z)
        if i < 0: raise Error("Cell is not resident")
        self.cells[i].dirty = True
        self.cells[i].revision+=1

    def save(mut self) raises:
        self.prepare()
        # Explicit flush joins the worker before serializing the newest revisions.
        self.queue.close()
        self.saves.clear()
        var snapshots=List[CellSnapshot]()
        for i in range(len(self.cells)):
            if self.cells[i].dirty:
                snapshots.append(CellSnapshot(self.cells[i].x,self.cells[i].z,self.cells[i].revision,self.cells[i].scene.copy()))
        if self.terrain_dirty:snapshots.append(CellSnapshot(TERRAIN_CELL,TERRAIN_CELL,self.terrain_revision,self.terrain.scene()))
        self.store.commit(snapshots)
        self.terrain_dirty=False
        for i in range(len(self.cells)):self.cells[i].dirty=False

    def update(mut self, camera: Vec3) raises:
        self.prepare()
        if self.asynchronous:
            self.update_async(camera)
            return
        var cx = Int(camera.x//self.cell_size)
        var cz = Int(camera.z//self.cell_size)
        # Save before mutation: a failed write retains all resident content.
        var needs_save=False
        for i in range(len(self.cells)):
            if abs(self.cells[i].x-cx) > self.radius or abs(self.cells[i].z-cz) > self.radius:
                if self.cells[i].dirty:
                    needs_save=True
        if needs_save:self.save()
        # Remove only evicted cells. Retained scenes and their derived caches
        # keep ownership and order instead of deep-copying every frame.
        for i in range(len(self.cells)-1,-1,-1):
            if abs(self.cells[i].x-cx)>self.radius or abs(self.cells[i].z-cz)>self.radius:_=self.cells.pop(i)
        var remaining = self.budget
        for ring in range(self.radius+1):
            for dz in range(-ring,ring+1):
                for dx in range(-ring,ring+1):
                    if max(abs(dx),abs(dz)) != ring or self.find(cx+dx,cz+dz) >= 0: continue
                    if remaining == 0: return
                    var path = self.path(cx+dx,cz+dz)
                    var scene = Scene3D()
                    # access(F_OK) separates absent cells from parse/read failures.
                    if external_call["access",Int32](path.as_c_string_span(),Int32(0)) == 0:
                        scene = Scene3D.load(path)
                    else:
                        var error = external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
                        if error[] != 2: raise Error("Cannot access world cell")
                    self.cells.append(WorldCell(cx+dx,cz+dz,scene^))
                    remaining -= 1

    def ensure(mut self, x: Int, z: Int) raises -> Int:
        """Authoring operations can explicitly load an offscreen cell."""
        self.prepare()
        if x==TERRAIN_CELL or z==TERRAIN_CELL:raise Error("Reserved terrain cell cannot contain objects")
        var found=self.find(x,z)
        if found>=0:return found
        var path=self.path(x,z)
        var scene=Scene3D()
        if external_call["access",Int32](path.as_c_string_span(),Int32(0))==0:scene=Scene3D.load(path)
        else:
            var errno=external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
            if errno[]!=2:raise Error("Cannot access world cell")
        self.cells.append(WorldCell(x,z,scene^))
        return len(self.cells)-1

    def request_save(mut self, x: Int, z: Int) raises:
        self.prepare()
        var found=self.find(x,z)
        if found<0 and not self.terrain_dirty:raise Error("Cannot save nonresident cell")
        if len(self.saves)>0:return
        if not self.terrain_dirty and not self.cells[found].dirty:return
        var job=StreamJob("save:"+self.directory,SAVE_WORLD_JOB,TerrainConfig(),path=self.directory.copy(),priority=-100)
        for cell in self.cells:
            if cell.dirty:job.snapshots.append(CellSnapshot(cell.x,cell.z,cell.revision,cell.scene.copy()))
        if self.terrain_dirty:job.snapshots.append(CellSnapshot(TERRAIN_CELL,TERRAIN_CELL,self.terrain_revision,self.terrain.scene()))
        if self.queue.submit(job^):
            if self.terrain_dirty:self.saves[self.path(TERRAIN_CELL,TERRAIN_CELL)]=self.terrain_revision
            for cell in self.cells:
                if cell.dirty:self.saves[self.path(cell.x,cell.z)]=cell.revision

    def update_async(mut self, camera: Vec3) raises:
        var cx=Int(camera.x//self.cell_size)
        var cz=Int(camera.z//self.cell_size)
        for _ in range(self.budget):
            var result=self.queue.take()
            if not result:break
            var job=result.value().copy()
            if job.kind==SAVE_WORLD_JOB:self.saves.clear()
            if job.error.byte_length()>0:raise Error(job.error)
            var found=self.find(job.x,job.z)
            if job.kind==SAVE_WORLD_JOB:
                self.store.commits+=1
                for snapshot in job.snapshots:
                    if snapshot.x==TERRAIN_CELL and snapshot.z==TERRAIN_CELL:
                        if self.terrain_revision==snapshot.revision:self.terrain_dirty=False
                        continue
                    var resident=self.find(snapshot.x,snapshot.z)
                    if resident>=0 and self.cells[resident].revision==snapshot.revision:self.cells[resident].dirty=False
            elif found<0 and abs(job.x-cx)<=self.radius and abs(job.z-cz)<=self.radius:
                self.cells.append(WorldCell(job.x,job.z,job.scene.copy()))
        if self.terrain_dirty:self.request_save(TERRAIN_CELL,TERRAIN_CELL)
        for i in range(len(self.cells)):
            if abs(self.cells[i].x-cx)>self.radius or abs(self.cells[i].z-cz)>self.radius:
                self.request_save(self.cells[i].x,self.cells[i].z)
        for i in range(len(self.cells)-1,-1,-1):
            if not self.cells[i].dirty and (abs(self.cells[i].x-cx)>self.radius or abs(self.cells[i].z-cz)>self.radius):_=self.cells.pop(i)
        # Retain dirty data under failed/slow I/O; throttle new residency instead
        # of accumulating unlimited cells during repeated edited teleports.
        if len(self.cells)>=(2*self.radius+1)*(2*self.radius+1)+8:return
        for ring in range(self.radius+1):
            for dz in range(-ring,ring+1):
                for dx in range(-ring,ring+1):
                    if max(abs(dx),abs(dz))!=ring or self.find(cx+dx,cz+dz)>=0:continue
                    var path=self.path(cx+dx,cz+dz)
                    _=self.queue.submit(StreamJob("load:"+path,LOAD_CELL_JOB,TerrainConfig(),cx+dx,cz+dz,path=path))

    def close(mut self) raises:
        self.save()
        self.store.close()
