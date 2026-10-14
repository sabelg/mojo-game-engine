"""Deterministic CPU terrain generation, safe to run on worker threads."""
from .math3d import Vec3
from .terrainlayer import TerrainLayer
from .math2d import Vec2
from .mesh import Mesh
from std.math import isfinite

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

struct TerrainConfig(Copyable, Movable):
    var layer: TerrainLayer
    var seed: Int
    var chunk_size: Float64
    var radius: Int
    var resolution: Int
    var chunks_per_update: Int

    def __init__(out self, seed: Int = 42, chunk_size: Float64 = 64, radius: Int = 4, resolution: Int = 32, chunks_per_update: Int = 2) raises:
        if not isfinite(chunk_size) or chunk_size <= 0 or radius < 1 or radius > 16 or resolution < 4 or resolution > 128 or resolution%4 != 0 or chunks_per_update < 1:
            raise Error("Invalid terrain configuration")
        self.layer=TerrainLayer()
        self.seed = seed
        self.chunk_size = chunk_size
        self.radius = radius
        self.resolution = resolution
        self.chunks_per_update = chunks_per_update

    def height(self, x: Float64, z: Float64) -> Float64:
        return self.layer.sample(x,z).height+smooth_noise(x/240,z/240,self.seed)*32+smooth_noise(x/90,z/90,self.seed+1)*10+smooth_noise(x/28,z/28,self.seed+2)*2

    def normal(self, x: Float64, z: Float64) -> Vec3:
        return Vec3(self.height(x-0.5,z)-self.height(x+0.5,z),1,self.height(x,z-0.5)-self.height(x,z+0.5)).unit()

    def mesh_bytes(self,lod: Int) -> Int:
        """Live vertex/index payload including the four duplicated skirts."""
        var n=self.resolution>>lod
        return (n+1)*(n+1)*32+n*n*24+n*864+((n+1)*(n+1)+n*24)*16*Int(self.layer.has_paint)

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
        if self.layer.has_paint:
            for vertex in range(len(mesh.vertices)//8):
                var color=self.layer.sample(ox+Float64(mesh.vertices[vertex*8]),oz+Float64(mesh.vertices[vertex*8+2])).color
                mesh.colors.extend([Float32(color.x),Float32(color.y),Float32(color.z),Float32(1)])
        return mesh^
