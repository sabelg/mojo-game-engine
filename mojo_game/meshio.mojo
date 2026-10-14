"""Versioned cooked mesh reader. Cooking is offline; runtime is native Mojo."""
from .mesh import Mesh,MorphTarget,load_obj
from .math3d import Vec3
from .math2d import Vec2
from std.math import isfinite
from .assetio import BinaryAsset,ASSET_MESH
from .durableio import read_bounded

def load_mesh(path: String) raises -> Mesh:
    if path.endswith(".obj"):return load_obj(path)
    if path.endswith(".atlasmeshb"):
        var source=BinaryAsset(path,ASSET_MESH)
        var vertices=source.count(2000000)
        var indices=source.count(6000000)
        source.require(vertices*32+indices*4)
        var mesh=Mesh()
        for _ in range(vertices):
            var values=List[Float64]()
            for _ in range(8):values.append(source.floating(4))
            _=mesh.vertex(Vec3(values[0],values[1],values[2]),Vec3(values[3],values[4],values[5]),Vec2(values[6],values[7]))
        for _ in range(indices):mesh.indices.append(UInt32(source.uint(4)))
        if source.cursor<len(source.bytes):
            if source.uint(4)!=0x47454f31:raise Error("Unknown binary geometry extension")
            var tangents=source.uint(4)
            var targets=source.count(64)
            if tangents>1:raise Error("Invalid binary tangent flag")
            source.require(Int(tangents)*vertices*16+targets*(8+vertices*36))
            if tangents:
                for _ in range(vertices*4):mesh.tangents.append(Float32(source.floating(4)))
            for _ in range(targets):
                mesh.morph_weights.append(source.floating())
                var target=MorphTarget()
                for _ in range(vertices*9):target.deltas.append(Float32(source.floating(4)))
                mesh.morphs.append(target^)
            if source.cursor<len(source.bytes):
                if source.uint(4)!=0x434f4c31:raise Error("Unknown binary color extension")
                source.require(vertices*16)
                for _ in range(vertices*4):mesh.colors.append(Float32(source.floating(4)))
        source.finish()
        mesh.validate()
        return mesh^
    var source: String
    source=read_bounded(path)
    var lines=source.split("\n")
    if len(lines)==0 or String(lines[0])!="ATLAS_MESH_1":raise Error("Unsupported cooked mesh")
    var mesh=Mesh()
    for i in range(1,len(lines)):
        var fields=String(lines[i]).split()
        if len(fields)==0:continue
        if fields[0]=="v" and len(fields)==9:
            var values=List[Float64]()
            for j in range(1,9):
                var value=Float64(String(fields[j]))
                if not isfinite(value):raise Error("Non-finite cooked vertex")
                values.append(value)
            _=mesh.vertex(Vec3(values[0],values[1],values[2]),Vec3(values[3],values[4],values[5]),Vec2(values[6],values[7]))
        elif fields[0]=="i" and len(fields)==4:
            for j in range(1,4):
                var index=Int(String(fields[j]))
                if index<0:raise Error("Negative cooked index")
                mesh.indices.append(UInt32(index))
        else:raise Error("Invalid cooked mesh record")
    mesh.validate()
    return mesh^
