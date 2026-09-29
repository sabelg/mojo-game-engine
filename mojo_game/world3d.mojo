"""Deterministic terrain, chunk residency, LOD skirts and budgeted GPU uploads.

Generation is synchronous but bounded by chunks_per_update. Terrain meshes use
local coordinates; global offsets remain Float64 until camera-relative upload.
"""
from .math3d import Vec3
from .math2d import Vec2
from .mesh import Mesh
from .transform3d import Transform3D, Mat4
from .graphics3d import Graphics3D
from .scene3d import Material
from .spatial import Bounds3D, Frustum


def lattice(x: Int, z: Int, seed: Int) -> Float64:
    var bits = UInt64(x)*UInt64(0x9E3779B185EBCA87)+UInt64(z)*UInt64(0xC2B2AE3D27D4EB4F)+UInt64(seed)
    bits = (bits ^ (bits >> 30))*UInt64(0xBF58476D1CE4E5B9)
    bits = (bits ^ (bits >> 27))*UInt64(0x94D049BB133111EB)
    bits = bits ^ (bits >> 31)
    return Float64(bits & 0xFFFFFF)/Float64(0xFFFFFF)*2-1

def smooth_noise(x: Float64, z: Float64, seed: Int) -> Float64:
    var ix = Int(x//1)
    var iz = Int(z//1)
    var fx = x-Float64(ix)
    var fz = z-Float64(iz)
    fx = fx*fx*(3-2*fx)
    fz = fz*fz*(3-2*fz)
    var a = lattice(ix,iz,seed)*(1-fx)+lattice(ix+1,iz,seed)*fx
    var b = lattice(ix,iz+1,seed)*(1-fx)+lattice(ix+1,iz+1,seed)*fx
    return a*(1-fz)+b*fz

struct TerrainConfig(ImplicitlyCopyable, Movable):
    var seed: Int
    var chunk_size: Float64
    var radius: Int
    var resolution: Int
    var chunks_per_update: Int

    def __init__(out self, seed: Int = 42, chunk_size: Float64 = 64, radius: Int = 4, resolution: Int = 32, chunks_per_update: Int = 2) raises:
        if chunk_size <= 0 or radius < 1 or radius > 16 or resolution < 4 or resolution > 128 or resolution%4 != 0 or chunks_per_update < 1:
            raise Error("Invalid terrain configuration")
        self.seed = seed
        self.chunk_size = chunk_size
        self.radius = radius
        self.resolution = resolution
        self.chunks_per_update = chunks_per_update

    def height(self, x: Float64, z: Float64) -> Float64:
        return smooth_noise(x/240,z/240,self.seed)*32+smooth_noise(x/90,z/90,self.seed+1)*10+smooth_noise(x/28,z/28,self.seed+2)*2

    def normal(self, x: Float64, z: Float64) -> Vec3:
        return Vec3(self.height(x-0.5,z)-self.height(x+0.5,z),1,self.height(x,z-0.5)-self.height(x,z+0.5)).unit()

    def mesh(self, cx: Int, cz: Int, lod: Int) raises -> Mesh:
        if lod < 0 or lod > 2: raise Error("Invalid terrain LOD")
        var mesh = Mesh()
        var resolution = self.resolution >> lod
        var spacing = self.chunk_size/Float64(resolution)
        var ox = Float64(cx)*self.chunk_size
        var oz = Float64(cz)*self.chunk_size
        for z in range(resolution+1):
            for x in range(resolution+1):
                var wx = ox+Float64(x)*spacing
                var wz = oz+Float64(z)*spacing
                _ = mesh.vertex(Vec3(Float64(x)*spacing,self.height(wx,wz),Float64(z)*spacing),self.normal(wx,wz),Vec2(wx/16,wz/16))
        for z in range(resolution):
            for x in range(resolution):
                var a = UInt32(z*(resolution+1)+x)
                var b = a+UInt32(resolution+1)
                mesh.indices.append(a)
                mesh.indices.append(b)
                mesh.indices.append(a+1)
                mesh.indices.append(a+1)
                mesh.indices.append(b)
                mesh.indices.append(b+1)
        # Vertical skirts hide T-junction cracks between neighboring resolutions.
        for side in range(4):
            for i in range(resolution):
                var ax = Float64(i)*spacing
                var az: Float64 = 0
                var bx = Float64(i+1)*spacing
                var bz: Float64 = 0
                if side == 1:
                    az = self.chunk_size
                    bz = self.chunk_size
                elif side == 2:
                    az = ax
                    bz = bx
                    ax = 0
                    bx = 0
                elif side == 3:
                    az = ax
                    bz = bx
                    ax = self.chunk_size
                    bx = self.chunk_size
                var a = Vec3(ax,self.height(ox+ax,oz+az),az)
                var b = Vec3(bx,self.height(ox+bx,oz+bz),bz)
                var down = Vec3(0,8,0)
                mesh.triangle(a,b,b-down)
                mesh.triangle(a,b-down,a-down)
        return mesh^

@fieldwise_init
struct TerrainChunk(ImplicitlyCopyable, Movable):
    var x: Int
    var z: Int
    var lod: Int
    var handle: Int

struct WorldStreamer:
    var config: TerrainConfig
    var chunks: List[TerrainChunk]
    var uploads: Int
    var evictions: Int

    def __init__(out self, config: TerrainConfig):
        self.config = config
        self.chunks = List[TerrainChunk]()
        self.uploads = 0
        self.evictions = 0

    def find(self, x: Int, z: Int) -> Int:
        for i in range(len(self.chunks)):
            if self.chunks[i].x == x and self.chunks[i].z == z: return i
        return -1

    def lod(self, dx: Int, dz: Int) -> Int:
        var distance = max(abs(dx),abs(dz))
        return 0 if distance <= 1 else (1 if distance <= 2 else 2)

    def update(mut self, device: Graphics3D, camera: Vec3) raises:
        var cx = Int(camera.x//self.config.chunk_size)
        var cz = Int(camera.z//self.config.chunk_size)
        var radius = self.config.radius
        var kept = List[TerrainChunk]()
        for chunk in self.chunks:
            if abs(chunk.x-cx) > radius or abs(chunk.z-cz) > radius:
                device.release(chunk.handle)
                self.evictions += 1
            else: kept.append(chunk)
        self.chunks = kept^
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
                    if found >= 0 and self.chunks[found].lod == lod: continue
                    if budget == 0: return
                    var mesh = self.config.mesh(x,z,lod)
                    var handle = device.upload(mesh)
                    var chunk = TerrainChunk(x,z,lod,handle)
                    if found >= 0:
                        device.release(self.chunks[found].handle)
                        self.chunks[found] = chunk
                    else: self.chunks.append(chunk)
                    self.uploads += 1
                    budget -= 1

    def clear(mut self, device: Graphics3D) raises:
        for chunk in self.chunks: device.release(chunk.handle)
        self.chunks.clear()

    def draw(self, device: Graphics3D, origin: Vec3, shadow: Bool = False, view_projection: Mat4 = Mat4(), cull: Bool = False) raises:
        var material = Material(Vec3(0.22,0.36,0.14),roughness=0.95)
        var frustum = Frustum(view_projection)
        for chunk in self.chunks:
            var corner = Vec3(Float64(chunk.x)*self.config.chunk_size,-52,Float64(chunk.z)*self.config.chunk_size)
            if cull and not frustum.visible(Bounds3D(corner,corner+Vec3(self.config.chunk_size,96,self.config.chunk_size)),origin): continue
            var matrix = Transform3D(Vec3(Float64(chunk.x)*self.config.chunk_size,0,Float64(chunk.z)*self.config.chunk_size)).matrix()
            if shadow: device.shadow(chunk.handle,matrix,origin)
            else: device.draw(chunk.handle,matrix,material,origin)
