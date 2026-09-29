"""Budgeted, disk-backed world cells for authored scene content.

Cell files contain world-space root transforms. The caller owns the directory
and stable asset table. Edits must be marked dirty; dirty cells are saved before
eviction. Loading errors propagate instead of silently discarding content.
"""
from std.ffi import external_call
from .math3d import Vec3
from .scene3d import Scene3D

struct WorldCell(Copyable, Movable):
    var x: Int
    var z: Int
    var scene: Scene3D
    var dirty: Bool

    def __init__(out self, x: Int, z: Int, var scene: Scene3D):
        self.x = x
        self.z = z
        self.scene = scene^
        self.dirty = False

struct WorldPartition:
    var directory: String
    var cell_size: Float64
    var radius: Int
    var budget: Int
    var cells: List[WorldCell]

    def __init__(out self, var directory: String, cell_size: Float64 = 256, radius: Int = 1, budget: Int = 2) raises:
        if cell_size <= 0 or radius < 0 or radius > 16 or budget < 1: raise Error("Invalid world partition configuration")
        self.directory = directory^
        self.cell_size = cell_size
        self.radius = radius
        self.budget = budget
        self.cells = List[WorldCell]()

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

    def save(mut self) raises:
        for i in range(len(self.cells)):
            if self.cells[i].dirty:
                self.cells[i].scene.save(self.path(self.cells[i].x,self.cells[i].z))
                self.cells[i].dirty = False

    def update(mut self, camera: Vec3) raises:
        var cx = Int(camera.x//self.cell_size)
        var cz = Int(camera.z//self.cell_size)
        # Save before mutation: a failed write retains all resident content.
        for i in range(len(self.cells)):
            if abs(self.cells[i].x-cx) > self.radius or abs(self.cells[i].z-cz) > self.radius:
                if self.cells[i].dirty:
                    self.cells[i].scene.save(self.path(self.cells[i].x,self.cells[i].z))
                    self.cells[i].dirty = False
        var kept = List[WorldCell]()
        for i in range(len(self.cells)):
            if abs(self.cells[i].x-cx) <= self.radius and abs(self.cells[i].z-cz) <= self.radius:
                kept.append(self.cells[i].copy())
        self.cells = kept^
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
