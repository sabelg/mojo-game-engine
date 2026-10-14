"""Deterministic terrain, chunk residency, LOD skirts and budgeted GPU uploads.

Generation may use a shared CPU scheduler, bounded by chunks_per_update. Meshes use
local coordinates; global offsets remain Float64 until camera-relative upload.
"""
from .math3d import Vec3
from .math2d import Vec2
from .mesh import Mesh
from .transform3d import Transform3D, Mat4
from .graphics3d import Graphics3D
from .scene3d import Material
from .spatial import Bounds3D, Frustum


from .terrain import TerrainConfig
from .terrainlayer import TerrainLayer
from .streaming import StreamQueue,StreamJob,TERRAIN_JOB,StreamScheduler
from std.ffi import external_call
from std.collections import Dict
from std.math import isfinite

struct TerrainChunk(ImplicitlyCopyable, Movable):
    var x: Int
    var z: Int
    var lod: Int
    var handle: Int
    var revision: Int
    var painted: Bool
    var min_y: Float64
    var max_y: Float64
    var previous_handle: Int
    var previous_bytes: Int
    var previous_painted: Bool
    var fade: Float64
    def __init__(out self,x: Int,z: Int,lod: Int,handle: Int,revision: Int=0,painted: Bool=False,min_y: Float64=-52,max_y: Float64=44):
        self.x=x
        self.z=z
        self.lod=lod
        self.handle=handle
        self.revision=revision
        self.painted=painted
        self.min_y=min_y
        self.max_y=max_y
        self.previous_handle=-1;self.previous_bytes=0;self.previous_painted=False;self.fade=1

struct WorldStreamer:
    var config: TerrainConfig
    var chunks: List[TerrainChunk]
    var uploads: Int
    var evictions: Int
    var asynchronous: Bool
    var upload_ms: Float64
    var queue: StreamQueue
    var center_x: Int
    var center_z: Int
    var index: Dict[String,Int]
    var mesh_byte_budget: Int
    var lod_bias: Int
    var revision: Int
    var transition_seconds: Float64
    var transition_count: Int
    var immediate_count: Int

    def __init__(out self, config: TerrainConfig, asynchronous: Bool=False, upload_ms: Float64=2,scheduler: Optional[StreamScheduler]=None,mesh_byte_budget: Int=256*1024*1024,transition_seconds: Float64=0) raises:
        self.config = config.copy()
        self.chunks = List[TerrainChunk]()
        self.uploads = 0
        self.evictions = 0
        if upload_ms<=0:raise Error("Invalid upload time budget")
        self.asynchronous=asynchronous
        self.upload_ms=upload_ms
        self.queue=StreamQueue(scheduler=scheduler)
        self.center_x=Int.MAX
        self.center_z=Int.MAX
        self.index=Dict[String,Int]()
        if mesh_byte_budget<=0:raise Error("Invalid terrain residency budget")
        self.mesh_byte_budget=mesh_byte_budget
        self.lod_bias=0
        self.revision=0
        if not isfinite(transition_seconds) or transition_seconds<0 or transition_seconds>2:raise Error("Invalid terrain transition duration")
        self.transition_seconds=transition_seconds;self.transition_count=0;self.immediate_count=0
        while self.resident_bytes()>mesh_byte_budget and self.lod_bias<2:self.lod_bias+=1
        if self.resident_bytes()>mesh_byte_budget:raise Error("Terrain neighborhood exceeds budget even at minimum quality")

    def set_layer(mut self,layer: TerrainLayer,revision: Int) raises:
        if revision==self.revision:return
        var previous=self.config.layer.copy()
        self.config.layer=layer.copy()
        if self.resident_bytes()+self.transition_bytes()>self.mesh_byte_budget:
            self.config.layer=previous^
            raise Error("Painted terrain and retained transitions exceed residency budget")
        self.revision=revision
        self.queue.invalidate()
        self.center_x=Int.MAX
        self.center_z=Int.MAX

    def find(self, x: Int, z: Int) -> Int:
        var key=String(x)+":"+String(z)
        return self.index.get(key,-1)

    def lod(self, dx: Int, dz: Int) -> Int:
        var distance = max(abs(dx),abs(dz))
        return min(2,(0 if distance <= 1 else (1 if distance <= 2 else 2))+self.lod_bias)

    def resident_bytes(self) -> Int:
        """Worst-case live mesh payload; allocator pages/staging are separate."""
        var total=0
        for z in range(-self.config.radius,self.config.radius+1):
            for x in range(-self.config.radius,self.config.radius+1):total+=self.config.mesh_bytes(self.lod(x,z))
        return total

    def rebuild_index(mut self):
        self.index.clear()
        for i in range(len(self.chunks)):
            self.index[String(self.chunks[i].x)+":"+String(self.chunks[i].z)]=i

    def transition_bytes(self) -> Int:
        var total=0
        for chunk in self.chunks:total+=chunk.previous_bytes
        return total

    def advance(mut self,device: Graphics3D,dt: Float64) raises:
        if not isfinite(dt) or dt<0 or dt>1 or not isfinite(self.transition_seconds) or self.transition_seconds<0 or self.transition_seconds>2:raise Error("Invalid terrain transition time step")
        for i in range(len(self.chunks)):
            if self.chunks[i].previous_handle<0:continue
            self.chunks[i].fade=min(Float64(1),self.chunks[i].fade+dt/self.transition_seconds if self.transition_seconds>0 else Float64(1))
            if self.chunks[i].fade>=1:
                device.release(self.chunks[i].previous_handle)
                self.chunks[i].previous_handle=-1;self.chunks[i].previous_bytes=0

    def install(mut self,device: Graphics3D,found: Int,var chunk: TerrainChunk) raises:
        if found<0:
            self.chunks.append(chunk)
            return
        var previous=self.chunks[found]
        var bytes=self.config.mesh_bytes(previous.lod)
        if previous.painted and not self.config.layer.has_paint:
            # Retained color attributes need space even after paint is removed.
            var painted=self.config.copy();painted.layer.has_paint=True
            bytes=painted.mesh_bytes(previous.lod)
        if self.transition_seconds>0 and previous.lod!=chunk.lod and previous.revision==chunk.revision and self.resident_bytes()+self.transition_bytes()+bytes<=self.mesh_byte_budget:
            chunk.previous_handle=previous.handle;chunk.previous_bytes=bytes
            chunk.previous_painted=previous.painted;chunk.fade=0
            self.transition_count+=1
        else:
            device.release(previous.handle)
            self.immediate_count+=1
        self.chunks[found]=chunk

    def update(mut self, device: Graphics3D, camera: Vec3,dt: Float64=1.0/60) raises:
        for value in [camera.x,camera.y,camera.z]:
            if not isfinite(value) or abs(value/self.config.chunk_size)>Float64(1<<40):raise Error("Invalid terrain camera position")
        if self.asynchronous:
            self.update_async(device,camera,dt)
            return
        self.advance(device,dt)
        var cx = Int(camera.x//self.config.chunk_size)
        var cz = Int(camera.z//self.config.chunk_size)
        var radius = self.config.radius
        var kept = List[TerrainChunk]()
        for chunk in self.chunks:
            if abs(chunk.x-cx) > radius or abs(chunk.z-cz) > radius:
                device.release(chunk.handle)
                if chunk.previous_handle>=0:device.release(chunk.previous_handle)
                self.evictions += 1
            else: kept.append(chunk)
        self.chunks = kept^
        self.rebuild_index()
        var budget = self.config.chunks_per_update
        # Near-first rings; retain old LOD until replacement upload succeeds.
        for ring in range(radius+1):
            for dz in range(-ring,ring+1):
                for dx in range(-ring,ring+1):
                    if max(abs(dx),abs(dz)) != ring: continue
                    var x = cx+dx
                    var z = cz+dz
                    var lod = self.lod(dx,dz)
                    var found = self.find(x,z)
                    if found >= 0 and self.chunks[found].lod == lod and self.chunks[found].revision==self.revision: continue
                    if found>=0 and self.chunks[found].previous_handle>=0:continue
                    if budget == 0: return
                    var mesh = self.config.mesh(x,z,lod)
                    var handle = device.upload(mesh)
                    var chunk = TerrainChunk(x,z,lod,handle,self.revision,self.config.layer.has_paint,-52+self.config.layer.min_delta,44+self.config.layer.max_delta)
                    self.install(device,found,chunk)
                    self.rebuild_index()
                    self.uploads += 1
                    budget -= 1

    def clear(mut self, device: Graphics3D) raises:
        self.queue.close()
        self.index.clear()
        for chunk in self.chunks:
            device.release(chunk.handle)
            if chunk.previous_handle>=0:device.release(chunk.previous_handle)
        self.chunks.clear()

    def update_async(mut self, device: Graphics3D, camera: Vec3,dt: Float64=1.0/60) raises:
        for value in [camera.x,camera.y,camera.z]:
            if not isfinite(value) or abs(value/self.config.chunk_size)>Float64(1<<40):raise Error("Invalid terrain camera position")
        self.advance(device,dt)
        var cx=Int(camera.x//self.config.chunk_size)
        var cz=Int(camera.z//self.config.chunk_size)
        var lead_x=0 if self.center_x==Int.MAX else max(-2,min(2,cx-self.center_x))
        var lead_z=0 if self.center_z==Int.MAX else max(-2,min(2,cz-self.center_z))
        if cx!=self.center_x or cz!=self.center_z:
            self.queue.retain_terrain(cx,cz,self.config.radius,lead_x,lead_z,self.lod_bias)
            self.center_x=cx
            self.center_z=cz
        var kept=List[TerrainChunk]()
        for chunk in self.chunks:
            if abs(chunk.x-cx)>self.config.radius or abs(chunk.z-cz)>self.config.radius:
                device.release(chunk.handle)
                if chunk.previous_handle>=0:device.release(chunk.previous_handle)
                self.evictions+=1
            else:kept.append(chunk)
        self.chunks=kept^
        self.rebuild_index()
        var began=external_call["SDL_GetPerformanceCounter",UInt64]()
        var frequency=external_call["SDL_GetPerformanceFrequency",UInt64]()
        for _ in range(self.config.chunks_per_update):
            var result=self.queue.take()
            if not result:break
            var job=result.value().copy()
            if job.revision!=self.revision:continue
            if job.error.byte_length()>0:raise Error(job.error)
            var dx=job.x-cx
            var dz=job.z-cz
            if max(abs(dx),abs(dz))>self.config.radius or job.lod!=self.lod(dx,dz):continue
            var found=self.find(job.x,job.z)
            if found>=0 and self.chunks[found].previous_handle>=0:continue
            var handle=device.upload(job.mesh)
            var chunk=TerrainChunk(job.x,job.z,job.lod,handle,self.revision,self.config.layer.has_paint,-52+self.config.layer.min_delta,44+self.config.layer.max_delta)
            self.install(device,found,chunk)
            self.uploads+=1
            self.rebuild_index()
            if Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-began)*1000/Float64(frequency)>=self.upload_ms:break
        for ring in range(self.config.radius+1):
            for dz in range(-ring,ring+1):
                for dx in range(-ring,ring+1):
                    if max(abs(dx),abs(dz))!=ring:continue
                    var found=self.find(cx+dx,cz+dz)
                    var lod=self.lod(dx,dz)
                    if found>=0 and self.chunks[found].previous_handle>=0:continue
                    if found>=0 and self.chunks[found].lod==lod and self.chunks[found].revision==self.revision:continue
                    var key=String(cx+dx)+":"+String(cz+dz)+":"+String(lod)
                    var priority=ring*32+max(abs(dx-lead_x),abs(dz-lead_z))
                    var job=StreamJob(key+":"+String(self.revision),TERRAIN_JOB,self.config,cx+dx,cz+dz,lod,priority=priority)
                    job.revision=self.revision
                    _=self.queue.submit(job^)

    def draw(self, device: Graphics3D, origin: Vec3, shadow: Bool = False, view_projection: Mat4 = Mat4(), cull: Bool = False) raises:
        var frustum = Frustum(view_projection)
        for chunk in self.chunks:
            var material=Material(Vec3(1,1,1) if chunk.painted else Vec3(.22,.36,.14),roughness=.95)
            var corner = Vec3(Float64(chunk.x)*self.config.chunk_size,chunk.min_y,Float64(chunk.z)*self.config.chunk_size)
            if cull and not frustum.visible(Bounds3D(corner,corner+Vec3(self.config.chunk_size,chunk.max_y-chunk.min_y,self.config.chunk_size)),origin): continue
            var matrix = Transform3D(Vec3(Float64(chunk.x)*self.config.chunk_size,0,Float64(chunk.z)*self.config.chunk_size)).matrix()
            if chunk.previous_handle>=0:
                var matrices: List[Mat4]=[matrix]
                var previous_material=Material(Vec3(1,1,1) if chunk.previous_painted else Vec3(.22,.36,.14),roughness=.95)
                device.draw_lod_instances(chunk.previous_handle,matrices,chunk.fade,material=previous_material,origin=origin,shadow=shadow)
                device.draw_lod_instances(chunk.handle,matrices,chunk.fade,True,material,origin,shadow)
            elif shadow:device.shadow(chunk.handle,matrix,origin)
            else:device.draw(chunk.handle,matrix,material,origin)
