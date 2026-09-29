"""Indexed position/normal/UV meshes and OBJ import. Convex polygons triangulated."""
from .math3d import Vec3
from std.math import isfinite
from .math2d import Vec2

struct Mesh(Copyable, Movable):
    var vertices: List[Float32]
    var indices: List[UInt32]
    var minimum: Vec3
    var maximum: Vec3

    def __init__(out self):
        self.vertices = List[Float32]()
        self.indices = List[UInt32]()
        self.minimum = Vec3(0, 0, 0)
        self.maximum = Vec3(0, 0, 0)

    def vertex(mut self, p: Vec3, normal: Vec3, uv: Vec2 = Vec2(0, 0)) -> UInt32:
        var index = UInt32(len(self.vertices)//8)
        if index == 0:
            self.minimum = p
            self.maximum = p
        else:
            self.minimum = Vec3(min(self.minimum.x, p.x), min(self.minimum.y, p.y), min(self.minimum.z, p.z))
            self.maximum = Vec3(max(self.maximum.x, p.x), max(self.maximum.y, p.y), max(self.maximum.z, p.z))
        self.vertices.append(Float32(p.x))
        self.vertices.append(Float32(p.y))
        self.vertices.append(Float32(p.z))
        self.vertices.append(Float32(normal.x))
        self.vertices.append(Float32(normal.y))
        self.vertices.append(Float32(normal.z))
        self.vertices.append(Float32(uv.x))
        self.vertices.append(Float32(uv.y))
        return index

    def triangle(mut self, a: Vec3, b: Vec3, c: Vec3):
        var normal = (b-a).cross(c-a).unit()
        self.indices.append(self.vertex(a, normal, Vec2(0, 0)))
        self.indices.append(self.vertex(b, normal, Vec2(1, 0)))
        self.indices.append(self.vertex(c, normal, Vec2(1, 1)))

    def validate(self) raises:
        if len(self.vertices) == 0 or len(self.vertices)%8 != 0 or len(self.indices)%3 != 0 or len(self.indices) == 0:
            raise Error("Invalid mesh layout")
        for value in self.vertices:
            if not isfinite(value): raise Error("Non-finite mesh vertex")
        for index in self.indices:
            if Int(index) >= len(self.vertices)//8: raise Error("Mesh index out of bounds")

    @staticmethod
    def cube() -> Self:
        var mesh = Self()
        var p: List[Vec3] = [Vec3(-0.5,-0.5,-0.5),Vec3(0.5,-0.5,-0.5),Vec3(0.5,0.5,-0.5),Vec3(-0.5,0.5,-0.5),Vec3(-0.5,-0.5,0.5),Vec3(0.5,-0.5,0.5),Vec3(0.5,0.5,0.5),Vec3(-0.5,0.5,0.5)]
        var faces: List[Int] = [0,3,2,1, 4,5,6,7, 0,1,5,4, 3,7,6,2, 0,4,7,3, 1,2,6,5]
        for i in range(0, len(faces), 4):
            mesh.triangle(p[faces[i]], p[faces[i+1]], p[faces[i+2]])
            mesh.triangle(p[faces[i]], p[faces[i+2]], p[faces[i+3]])
        return mesh^

    @staticmethod
    def sphere(segments: Int = 24, rings: Int = 12) raises -> Self:
        from std.math import sin, cos
        if segments < 3 or rings < 2: raise Error("Invalid sphere tessellation")
        var mesh = Self()
        for j in range(rings+1):
            var latitude = Float64(j)*3.141592653589793/Float64(rings)
            for i in range(segments+1):
                var longitude = Float64(i)*6.283185307179586/Float64(segments)
                var n = Vec3(sin(latitude)*cos(longitude),cos(latitude),sin(latitude)*sin(longitude))
                _ = mesh.vertex(n,n,Vec2(Float64(i)/Float64(segments),Float64(j)/Float64(rings)))
        for j in range(rings):
            for i in range(segments):
                var a = UInt32(j*(segments+1)+i)
                var b = a+UInt32(segments+1)
                mesh.indices.append(a)
                mesh.indices.append(a+1)
                mesh.indices.append(b)
                mesh.indices.append(a+1)
                mesh.indices.append(b+1)
                mesh.indices.append(b)
        return mesh^

def obj_index(text: String, length: Int) raises -> Int:
    var index = Int(text)
    if index == 0: raise Error("OBJ index zero is invalid")
    index = index-1 if index > 0 else length+index
    if index < 0 or index >= length: raise Error("OBJ index out of bounds")
    return index

def parse_obj(source: String) raises -> Mesh:
    var positions = List[Vec3]()
    var normals = List[Vec3]()
    var uvs = List[Vec2]()
    var mesh = Mesh()
    for line in source.split("\n"):
        var fields = String(line).split()
        if len(fields) == 0: continue
        if fields[0] == "v":
            if len(fields) < 4: raise Error("OBJ position needs xyz")
            positions.append(Vec3(Float64(String(fields[1])), Float64(String(fields[2])), Float64(String(fields[3]))))
        elif fields[0] == "vn":
            if len(fields) < 4: raise Error("OBJ normal needs xyz")
            normals.append(Vec3(Float64(String(fields[1])), Float64(String(fields[2])), Float64(String(fields[3]))).unit())
        elif fields[0] == "vt":
            if len(fields) < 3: raise Error("OBJ UV needs two coordinates")
            uvs.append(Vec2(Float64(String(fields[1])), Float64(String(fields[2]))))
        elif fields[0] == "f":
            var face = List[Int]()
            for i in range(1, len(fields)):
                if fields[i].startswith("#"): break
                face.append(i)
            if len(face) < 3: raise Error("OBJ face needs three vertices")
            for i in range(1, len(face)-1):
                var corners: List[Int] = [face[0], face[i], face[i+1]]
                var points = List[Vec3]()
                var ns = List[Int]()
                var ts = List[Int]()
                for corner in corners:
                    var parts = String(fields[corner]).split("/")
                    if len(parts) > 3: raise Error("Invalid OBJ face token")
                    points.append(positions[obj_index(String(parts[0]), len(positions))])
                    var normal = -1
                    var uv = -1
                    if len(parts) > 1 and parts[1].byte_length() > 0: uv = obj_index(String(parts[1]), len(uvs))
                    if len(parts) > 2 and parts[2].byte_length() > 0: normal = obj_index(String(parts[2]), len(normals))
                    ns.append(normal)
                    ts.append(uv)
                var flat = (points[1]-points[0]).cross(points[2]-points[0]).unit()
                for j in range(3):
                    var normal = flat
                    var uv = Vec2(0, 0)
                    if ns[j] >= 0: normal = normals[ns[j]]
                    if ts[j] >= 0: uv = uvs[ts[j]]
                    var index = mesh.vertex(points[j], normal, uv)
                    mesh.indices.append(index)
    mesh.validate()
    return mesh^

def load_obj(path: String) raises -> Mesh:
    with open(path, "r") as file:
        return parse_obj(file.read())
