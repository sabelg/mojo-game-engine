"""Bounded unshadowed point/spot illumination with inverse-square attenuation.

Intensity is RGB luminous intensity, distinct from an area light's radiance.
Positions use world metres. Pass the current floating origin at submission.
"""
from std.math import cos,isfinite
from .math3d import Vec3
from .durableio import read_bounded
from std.collections import Dict

struct LocalLight3D(ImplicitlyCopyable, Movable):
    var position: Vec3
    var intensity: Vec3
    var direction: Vec3
    var inner: Float64
    var outer: Float64
    def __init__(out self,position: Vec3,intensity: Vec3):
        self.position=position
        self.intensity=intensity
        self.direction=Vec3(0,0,-1)
        self.inner=-1
        self.outer=-1

    @staticmethod
    def spot(position: Vec3,intensity: Vec3,direction: Vec3,inner_angle: Float64,outer_angle: Float64) raises -> Self:
        if not isfinite(inner_angle) or not isfinite(outer_angle) or inner_angle<0 or outer_angle<inner_angle or outer_angle>=3.14159265:raise Error("Invalid spot cone angles")
        if not isfinite(direction.length()) or direction.length()<1e-12:raise Error("Invalid spot direction")
        var result=Self(position,intensity)
        result.direction=direction.unit()
        result.inner=cos(inner_angle)
        result.outer=cos(outer_angle)
        return result


    @staticmethod
    def load(path: String) raises -> List[Self]:
        var lines=read_bounded(path,256*1024).split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_LOCAL_LIGHTS_1":raise Error("Unsupported local light format")
        var result=List[Self]()
        var ids=Dict[String,Bool]()
        for i in range(1,len(lines)):
            if String(lines[i]).byte_length()==0:continue
            var f=String(lines[i]).split("\t")
            if len(f)!=12 or len(result)>=32:raise Error("Invalid local light record or count")
            var identity=String(f[0])
            if identity.byte_length()==0 or identity in ids:raise Error("Invalid local light identity")
            ids[identity]=True
            for j in range(1,12):
                var v=Float64(String(f[j]))
                if not isfinite(v) or (j>=4 and j<=6 and (v<0 or v>1e9)):raise Error("Invalid local light scalar")
            var light=Self(Vec3(Float64(String(f[1])),Float64(String(f[2])),Float64(String(f[3]))),Vec3(Float64(String(f[4])),Float64(String(f[5])),Float64(String(f[6]))))
            light.direction=Vec3(Float64(String(f[7])),Float64(String(f[8])),Float64(String(f[9])))
            light.inner=Float64(String(f[10]))
            light.outer=Float64(String(f[11]))
            if light.outer < -1 or light.outer>light.inner or light.inner>1 or abs(light.direction.length()-1)>.0001:raise Error("Invalid local light cone")
            result.append(light)
        return result^
