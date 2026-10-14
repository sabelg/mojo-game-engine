"""Bounded shared CPU scheduler, client cancellation and owned prepared results.

All mutable scheduler state is under its SDL mutex. Workers hold no GPU handles.
ArcPointer pins state until the final owner joins every thread before destruction.
"""
from std.memory import ArcPointer
from std.ffi import external_call
from std.collections import Dict
from .sdl import Handle,NullableHandle
from .mesh import Mesh
from .triangle3d import TriangleMesh3D
from .transform3d import Mat4
from .scene3d import Scene3D
from .terrain import TerrainConfig
from .worldstore import CellSnapshot,commit_world

comptime TERRAIN_JOB=0
comptime LOAD_CELL_JOB=1
comptime SAVE_CELL_JOB=2
comptime SAVE_WORLD_JOB=3
comptime COLLISION_JOB=4

@fieldwise_init
struct StreamStats(ImplicitlyCopyable,Movable):
    var queued: Int
    var ready: Int
    var busy: Int
    var reserved_bytes: Int
    var peak_bytes: Int
    var accepted: Int
    var rejected: Int
    var completed: Int
    var cancelled: Int
    var errors: Int
    var work_ms: Float64

struct StreamJob(Copyable,Movable):
    var key: String
    var kind: Int
    var generation: Int
    var client: Int
    var serial: Int
    var priority: Int
    var x: Int
    var z: Int
    var lod: Int
    var revision: Int
    var path: String
    var config: TerrainConfig
    var mesh: Mesh
    var scene: Scene3D
    var snapshots: List[CellSnapshot]
    var error: String
    var bytes: Int
    var collision_paths: List[String]
    var collision_matrices: List[Mat4]
    var colliders: List[TriangleMesh3D]
    var asset_revision: UInt64
    def __init__(out self,var key: String,kind: Int,config: TerrainConfig,x: Int=0,z: Int=0,lod: Int=0,var path: String="",priority: Int=0):
        self.key=key^
        self.kind=kind
        self.generation=0
        self.client=0
        self.serial=0
        self.priority=priority
        self.x=x
        self.z=z
        self.lod=lod
        self.revision=0
        self.path=path^
        self.config=config.copy()
        self.mesh=Mesh()
        self.scene=Scene3D()
        self.snapshots=List[CellSnapshot]()
        self.error=String()
        self.bytes=0
        self.collision_paths=List[String]()
        self.collision_matrices=List[Mat4]()
        self.colliders=List[TriangleMesh3D]()
        self.asset_revision=0

struct BusyJob(Copyable,Movable):
    var client: Int
    var serial: Int
    var key: String
    var bytes: Int
    var kind: Int
    var x: Int
    var z: Int
    var lod: Int
    var cancelled: Bool
    def __init__(out self,job: StreamJob):
        self.client=job.client
        self.serial=job.serial
        self.key=job.key.copy()
        self.bytes=job.bytes
        self.kind=job.kind
        self.x=job.x
        self.z=job.z
        self.lod=job.lod
        self.cancelled=False

struct StreamState:
    var lock: NullableHandle
    var changed: NullableHandle
    var stop: Bool
    var threads: List[Handle]
    var workers: Int
    var next_client: Int
    var generations: Dict[Int,Int]
    var limits: Dict[Int,Int]
    var serial_clients: Dict[Int,Bool]
    var queued: List[StreamJob]
    var ready: List[StreamJob]
    var active: List[BusyJob]
    var bytes: Int
    var peak_bytes: Int
    var byte_limit: Int
    var job_limit: Int
    var save_reserve: Int
    var save_jobs: Int
    var accepted: Int
    var rejected: Int
    var completed: Int
    var cancelled: Int
    var errors: Int
    var work_ms: Float64
    def __init__(out self,byte_limit: Int,job_limit: Int,workers: Int,save_reserve: Int=0) raises:
        self.lock=None
        self.changed=None
        self.stop=False
        self.threads=List[Handle]()
        self.workers=workers
        self.next_client=0
        self.generations=Dict[Int,Int]()
        self.limits=Dict[Int,Int]()
        self.serial_clients=Dict[Int,Bool]()
        self.queued=List[StreamJob]()
        self.ready=List[StreamJob]()
        self.active=List[BusyJob]()
        self.bytes=0
        self.peak_bytes=0
        self.byte_limit=byte_limit
        self.job_limit=job_limit
        self.save_reserve=min(save_reserve,byte_limit//4)
        self.save_jobs=1 if save_reserve>0 and job_limit>workers else 0
        self.accepted=0
        self.rejected=0
        self.completed=0
        self.cancelled=0
        self.errors=0
        self.work_ms=0
        self.lock=external_call["SDL_CreateMutex",NullableHandle]()
        self.changed=external_call["SDL_CreateCondition",NullableHandle]()
        if not self.lock or not self.changed:raise Error("Cannot create scheduler synchronization")
    def start(mut self) raises:
        _=external_call["SDL_LockMutex",NoneType](self.lock.value())
        if len(self.threads)==self.workers:
            _=external_call["SDL_UnlockMutex",NoneType](self.lock.value())
            return
        self.stop=False
        var callback: def(UInt64) abi("C") thin -> Int32=stream_worker
        var name=String("atlas-worker")
        var failed=False
        while len(self.threads)<self.workers:
            var thread=external_call["SDL_CreateThreadRuntime",NullableHandle](Pointer(to=callback).unsafe_bitcast[Handle]()[],name.as_c_string_span(),UInt64(Int(Pointer(to=self))),NullableHandle(None),NullableHandle(None))
            if not thread:
                failed=True
                break
            self.threads.append(thread.value())
        _=callback
        _=name^
        _=external_call["SDL_UnlockMutex",NoneType](self.lock.value())
        if failed:
            self.shutdown()
            raise Error("Cannot create scheduler worker")
    def shutdown(mut self):
        if len(self.threads)>0:
            _=external_call["SDL_LockMutex",NoneType](self.lock.value())
            self.stop=True
            _=external_call["SDL_BroadcastCondition",NoneType](self.changed.value())
            _=external_call["SDL_UnlockMutex",NoneType](self.lock.value())
            for thread in self.threads:external_call["SDL_WaitThread",NoneType](thread,NullableHandle(None))
            self.threads.clear()
    def __deinit__(deinit self):
        self.shutdown()
        if self.changed:external_call["SDL_DestroyCondition",NoneType](self.changed.value())
        if self.lock:external_call["SDL_DestroyMutex",NoneType](self.lock.value())

def choose_job(state: StreamState) -> Int:
    var selected=-1
    var score=Int.MAX
    for i in range(len(state.queued)):
        var client=state.queued[i].client
        var eligible=True
        if state.serial_clients.get(client,True):
            for active in state.active:
                if active.client==client:eligible=False
        if not eligible:continue
        # Aging eventually promotes low-priority work even under continuous travel.
        var priority=state.queued[i].priority-(state.accepted-state.queued[i].serial)//8
        if priority<score:
            selected=i
            score=priority
    return selected

def stream_worker(address: UInt64) abi("C") -> Int32:
    var state=Pointer[StreamState,MutUntrackedOrigin](unsafe_from_address=Int(address))
    while True:
        _=external_call["SDL_LockMutex",NoneType](state[].lock.value())
        var selected=choose_job(state[])
        while not state[].stop and selected<0:
            _=external_call["SDL_WaitCondition",NoneType](state[].changed.value(),state[].lock.value())
            selected=choose_job(state[])
        if state[].stop:
            _=external_call["SDL_UnlockMutex",NoneType](state[].lock.value())
            break
        var job=state[].queued.pop(selected)
        state[].active.append(BusyJob(job))
        _=external_call["SDL_UnlockMutex",NoneType](state[].lock.value())
        var began=external_call["SDL_GetPerformanceCounter",UInt64]()
        try:
            if job.kind==TERRAIN_JOB:job.mesh=job.config.mesh(job.x,job.z,job.lod)
            elif job.kind==LOAD_CELL_JOB:
                var path=job.path.copy()
                if external_call["access",Int32](path.as_c_string_span(),Int32(0))==0:
                    var source: String
                    with open(path,"r") as file:source=file.read(job.bytes//16+1)
                    if source.byte_length()>job.bytes//16:raise Error("Cell exceeds streaming memory reservation")
                    job.scene=Scene3D.decode(source)
                else:
                    var errno=external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
                    if errno[]!=2:raise Error("Cannot access world cell")
            elif job.kind==COLLISION_JOB:
                if len(job.collision_paths)!=len(job.collision_matrices) or len(job.collision_paths)>256:raise Error("Invalid collision worker request")
                var total=0
                for i in range(len(job.collision_paths)):
                    var collider=TriangleMesh3D.load(job.collision_paths[i],job.collision_matrices[i],16*1024*1024-total,4*1024*1024)
                    total+=collider.payload_bytes()
                    job.colliders.append(collider^)
            elif job.kind==SAVE_CELL_JOB:job.scene.save(job.path)
            elif job.kind==SAVE_WORLD_JOB:commit_world(job.path,job.snapshots)
            else:raise Error("Unknown streaming job")
        except error:job.error=String(error)
        _=external_call["SDL_LockMutex",NoneType](state[].lock.value())
        state[].work_ms+=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-began)*1000/Float64(external_call["SDL_GetPerformanceFrequency",UInt64]())
        state[].completed+=1
        if job.error.byte_length()>0:state[].errors+=1
        var cancelled=False
        for i in range(len(state[].active)):
            if state[].active[i].serial==job.serial:
                cancelled=state[].active[i].cancelled
                _=state[].active.pop(i)
                break
        if not state[].stop and not cancelled and job.generation==state[].generations.get(job.client,-1):state[].ready.append(job^)
        else:
            state[].bytes-=job.bytes
            state[].cancelled+=1
        _=external_call["SDL_BroadcastCondition",NoneType](state[].changed.value())
        _=external_call["SDL_UnlockMutex",NoneType](state[].lock.value())
    return 0

struct StreamScheduler(Copyable,Movable):
    var state: ArcPointer[StreamState]
    def __init__(out self,workers: Int=4,byte_limit: Int=64*1024*1024,job_limit: Int=64,save_reserve: Int=4*1024*1024) raises:
        if workers<1 or workers>16 or byte_limit<4096 or job_limit<workers or save_reserve<0:raise Error("Invalid scheduler configuration")
        self.state=ArcPointer(StreamState(byte_limit,job_limit,workers,save_reserve))
    def stats(self) -> StreamStats:
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        var result=StreamStats(len(self.state[].queued),len(self.state[].ready),len(self.state[].active),self.state[].bytes,self.state[].peak_bytes,self.state[].accepted,self.state[].rejected,self.state[].completed,self.state[].cancelled,self.state[].errors,self.state[].work_ms)
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
        return result

struct StreamQueue:
    var state: ArcPointer[StreamState]
    var client: Int
    def __init__(out self,byte_limit: Int=64*1024*1024,job_limit: Int=8,scheduler: Optional[StreamScheduler]=None,serial: Bool=False) raises:
        if byte_limit<4096 or job_limit<1:raise Error("Invalid streaming limits")
        self.state=scheduler.value().state.copy() if scheduler else ArcPointer(StreamState(byte_limit,job_limit+1,1))
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        self.client=self.state[].next_client
        self.state[].next_client+=1
        self.state[].generations[self.client]=0
        self.state[].limits[self.client]=job_limit+1
        self.state[].serial_clients[self.client]=serial
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
    def start(mut self) raises:self.state[].start()
    def submit(mut self,var job: StreamJob) raises -> Bool:
        if job.kind==TERRAIN_JOB and (job.lod<0 or job.lod>2):raise Error("Invalid terrain worker LOD")
        if job.kind==TERRAIN_JOB:
            var n=(job.config.resolution>>job.lod)+1
            job.bytes=n*n*160+65536+job.config.layer.memory_bytes()*3
        elif job.kind==COLLISION_JOB:job.bytes=48*1024*1024
        elif job.kind==LOAD_CELL_JOB:job.bytes=min(self.state[].byte_limit,16*1024*1024)
        else:
            job.bytes=4096
            for node in job.scene.nodes:job.bytes+=2048+8*(node.name.byte_length()+node.asset_key.byte_length()+node.material_key.byte_length()+node.persistent_id.byte_length())
            for snapshot in job.snapshots:
                for node in snapshot.scene.nodes:job.bytes+=2048+8*(node.name.byte_length()+node.asset_key.byte_length()+node.material_key.byte_length()+node.persistent_id.byte_length())
        var available=self.state[].byte_limit-(0 if job.kind==SAVE_CELL_JOB or job.kind==SAVE_WORLD_JOB else self.state[].save_reserve)
        if job.bytes>available:raise Error("Streaming job exceeds configured reservation budget")
        self.start()
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        var accepted=True
        var count=0
        for active in self.state[].active:
            if active.client==self.client:
                count+=1
                if active.key==job.key and not active.cancelled:accepted=False
        for entry in self.state[].queued:
            if entry.client==self.client:
                count+=1
                if entry.key==job.key:accepted=False
        for entry in self.state[].ready:
            if entry.client==self.client:
                count+=1
                if entry.key==job.key:accepted=False
        var saving=job.kind==SAVE_CELL_JOB or job.kind==SAVE_WORLD_JOB
        var byte_limit=self.state[].byte_limit-(0 if saving else self.state[].save_reserve)
        var job_limit=self.state[].job_limit-(0 if saving else self.state[].save_jobs)
        if count>=self.state[].limits[self.client] or len(self.state[].queued)+len(self.state[].ready)+len(self.state[].active)>=job_limit or self.state[].bytes+job.bytes>byte_limit:accepted=False
        if accepted:
            self.state[].accepted+=1
            job.client=self.client
            job.serial=self.state[].accepted
            job.generation=self.state[].generations[self.client]
            self.state[].bytes+=job.bytes
            self.state[].peak_bytes=max(self.state[].peak_bytes,self.state[].bytes)
            self.state[].queued.append(job^)
            _=external_call["SDL_BroadcastCondition",NoneType](self.state[].changed.value())
        else:self.state[].rejected+=1
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
        return accepted
    def take(mut self) -> Optional[StreamJob]:
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        var selected=-1
        var priority=Int.MAX
        for i in range(len(self.state[].ready)):
            if self.state[].ready[i].client==self.client and self.state[].ready[i].priority<priority:
                priority=self.state[].ready[i].priority
                selected=i
        var result=Optional[StreamJob](None)
        if selected>=0:
            var job=self.state[].ready.pop(selected)
            self.state[].bytes-=job.bytes
            result=Optional[StreamJob](job^)
        _=external_call["SDL_BroadcastCondition",NoneType](self.state[].changed.value())
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
        return result^
    def discard_locked(mut self):
        self.state[].generations[self.client]=self.state[].generations.get(self.client,0)+1
        for i in range(len(self.state[].queued)-1,-1,-1):
            if self.state[].queued[i].client==self.client:
                self.state[].bytes-=self.state[].queued[i].bytes
                self.state[].cancelled+=1
                _=self.state[].queued.pop(i)
        for i in range(len(self.state[].ready)-1,-1,-1):
            if self.state[].ready[i].client==self.client:
                self.state[].bytes-=self.state[].ready[i].bytes
                self.state[].cancelled+=1
                _=self.state[].ready.pop(i)
        for i in range(len(self.state[].active)):
            if self.state[].active[i].client==self.client:self.state[].active[i].cancelled=True
    def invalidate(mut self):
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        self.discard_locked()
        _=external_call["SDL_BroadcastCondition",NoneType](self.state[].changed.value())
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
    def retain_terrain(mut self,cx: Int,cz: Int,radius: Int,lead_x: Int=0,lead_z: Int=0,lod_bias: Int=0):
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        for i in range(len(self.state[].queued)-1,-1,-1):
            if self.state[].queued[i].client!=self.client:continue
            var job=self.state[].queued[i].copy()
            var distance=max(abs(job.x-cx),abs(job.z-cz))
            var lod=min(2,(0 if distance<=1 else (1 if distance<=2 else 2))+lod_bias)
            if distance>radius or job.lod!=lod:
                self.state[].bytes-=job.bytes
                self.state[].cancelled+=1
                _=self.state[].queued.pop(i)
            else:self.state[].queued[i].priority=distance*32+max(abs(job.x-cx-lead_x),abs(job.z-cz-lead_z))
        for i in range(len(self.state[].ready)-1,-1,-1):
            if self.state[].ready[i].client!=self.client:continue
            var job=self.state[].ready[i].copy()
            var distance=max(abs(job.x-cx),abs(job.z-cz))
            var lod=min(2,(0 if distance<=1 else (1 if distance<=2 else 2))+lod_bias)
            if distance>radius or job.lod!=lod:
                self.state[].bytes-=job.bytes
                self.state[].cancelled+=1
                _=self.state[].ready.pop(i)
            else:self.state[].ready[i].priority=distance*32+max(abs(job.x-cx-lead_x),abs(job.z-cz-lead_z))
        for i in range(len(self.state[].active)):
            var active=self.state[].active[i].copy()
            if active.client!=self.client:continue
            var distance=max(abs(active.x-cx),abs(active.z-cz))
            var lod=min(2,(0 if distance<=1 else (1 if distance<=2 else 2))+lod_bias)
            if distance>radius or active.lod!=lod:self.state[].active[i].cancelled=True
        _=external_call["SDL_BroadcastCondition",NoneType](self.state[].changed.value())
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
    def stats(self) -> StreamStats:
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        var queued=0
        var ready=0
        var busy=0
        var bytes=0
        for job in self.state[].queued:
            if job.client==self.client:
                queued+=1
                bytes+=job.bytes
        for job in self.state[].ready:
            if job.client==self.client:
                ready+=1
                bytes+=job.bytes
        for job in self.state[].active:
            if job.client==self.client:
                busy+=1
                bytes+=job.bytes
        var result=StreamStats(queued,ready,busy,bytes,self.state[].peak_bytes,self.state[].accepted,self.state[].rejected,self.state[].completed,self.state[].cancelled,self.state[].errors,self.state[].work_ms)
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
        return result
    def pending(self) -> Int:
        var stats=self.stats()
        return stats.queued+stats.ready+stats.busy
    def peak_bytes(self) -> Int:return self.stats().peak_bytes
    def close(mut self):
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        self.discard_locked()
        var busy=True
        while busy:
            busy=False
            for job in self.state[].active:
                if job.client==self.client:busy=True
            if busy:_=external_call["SDL_WaitCondition",NoneType](self.state[].changed.value(),self.state[].lock.value())
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
        if self.state.count()==1:self.state[].shutdown()
    def __deinit__(deinit self):
        self.close()
        _=external_call["SDL_LockMutex",NoneType](self.state[].lock.value())
        try:
            _=self.state[].generations.pop(self.client)
            _=self.state[].limits.pop(self.client)
            _=self.state[].serial_clients.pop(self.client)
        except:pass
        _=external_call["SDL_UnlockMutex",NoneType](self.state[].lock.value())
