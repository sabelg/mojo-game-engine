"""USD light samples mapped to Atlas's one-sun and constant-SH environment path.

Finite distant-light angular extent uses a directional approximation. The caller
still builds shadow matrices and submits shadow geometry. Area lights, texture
maps, light linking, arbitrary graphs and animated samples need other systems.
"""
from std.math import isfinite
from std.collections import Dict
from .math3d import Vec3
from .transform3d import Mat4
from .environment3d import Environment3D
from .graphics3d import Graphics3D
from .durableio import read_bounded

struct AuthoredLighting3D(ImplicitlyCopyable, Movable):
    var direction: Vec3
    var sun: Vec3
    var environment: Vec3

    def __init__(out self):
        self.direction=Vec3(0,1,0)
        self.sun=Vec3(0,0,0)
        self.environment=Vec3(0,0,0)

    @staticmethod
    def load(path: String) raises -> Self:
        var lines=read_bounded(path,1024*1024).split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_LIGHTS_1":raise Error("Unsupported light format")
        var result=Self()
        var identities=Dict[String,Bool]()
        var distant=0
        for i in range(1,len(lines)):
            if String(lines[i]).byte_length()==0:continue
            var fields=String(lines[i]).split("\t")
            if len(fields)!=8 or len(identities)>=256:raise Error("Invalid light record or light budget")
            var identity=String(fields[0])
            if identity.byte_length()==0 or identity in identities:raise Error("Invalid/duplicate light identity")
            identities[identity]=True
            for j in range(2,8):
                var value=Float64(String(fields[j]))
                if not isfinite(value):raise Error("Non-finite light sample")
                if j>=5 and (value<0 or value>60000):raise Error("Light radiance outside 0..60000")
            var color=Vec3(Float64(String(fields[5])),Float64(String(fields[6])),Float64(String(fields[7])))
            if String(fields[1])=="DistantLight":
                distant+=1
                if distant>1:raise Error("Atlas light profile supports one distant light")
                result.direction=Vec3(Float64(String(fields[2])),Float64(String(fields[3])),Float64(String(fields[4])))
                if abs(result.direction.length()-1)>.0001:raise Error("Invalid light direction")
                result.sun=color
            elif String(fields[1])=="DomeLight":result.environment=result.environment+color
            else:raise Error("Unsupported runtime light type")
        _=Environment3D.constant(result.environment)
        return result

    def begin(self,device: Graphics3D,view_projection: Mat4,eye: Vec3=Vec3(0,0,0),fog: Float64=0,exposure: Float64=1) raises:
        device.hdr()
        device.environment(Environment3D.constant(self.environment))
        device.begin(view_projection,self.direction,fog)
        device.camera_origin(eye)
        device.lighting(Vec3(0,0,0),Vec3(0,0,0),self.sun,Vec3(0,0,0),exposure)

struct LightSample3D(ImplicitlyCopyable, Movable):
    var time: Float64
    var direction: Vec3
    var color: Vec3
    def __init__(out self,time: Float64,direction: Vec3,color: Vec3):
        self.time=time
        self.direction=direction
        self.color=color

struct AuthoredLightTrack3D(Copyable, Movable):
    var identity: String
    var distant: Bool
    var samples: List[LightSample3D]
    def __init__(out self,var identity: String,distant: Bool):
        self.identity=identity^
        self.distant=distant
        self.samples=List[LightSample3D]()

    def sample(self,time: Float64) raises -> LightSample3D:
        if not isfinite(time) or len(self.samples)==0:raise Error("Invalid light sampling request")
        var low=0
        var high=len(self.samples)-1
        while low<high:
            var mid=(low+high+1)//2
            if self.samples[mid].time<=time:low=mid
            else:high=mid-1
        var a=self.samples[low]
        var b=self.samples[min(low+1,len(self.samples)-1)]
        var t: Float64=0
        if b.time>a.time:t=max(0.0,min(1.0,(time-a.time)/(b.time-a.time)))
        return LightSample3D(time,(a.direction*(1-t)+b.direction*t).unit(),a.color*(1-t)+b.color*t)

    @staticmethod
    def evaluate(tracks: List[Self],base: AuthoredLighting3D,time: Float64) raises -> AuthoredLighting3D:
        var result=base
        for track in tracks:
            var value=track.sample(time)
            if track.distant:
                result.sun=value.color
                result.direction=value.direction
            else:result.environment=result.environment+value.color-track.samples[0].color
        return result

    @staticmethod
    def load(path: String) raises -> List[Self]:
        var lines=read_bounded(path,16*1024*1024).split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_LIGHT_TRACKS_1":raise Error("Unsupported light track format")
        var result=List[Self]()
        var indices=Dict[String,Int]()
        var count=0
        var suns=0
        for i in range(1,len(lines)):
            if String(lines[i]).byte_length()==0:continue
            count+=1
            var f=String(lines[i]).split("\t")
            if count>16384 or len(f)!=9:raise Error("Invalid light key or sample budget exceeded")
            var identity=String(f[0])
            var distant=String(f[1])=="DistantLight"
            if identity.byte_length()==0 or identity.byte_length()>4096 or (not distant and String(f[1])!="DomeLight"):raise Error("Invalid light track identity/type")
            if identity not in indices:
                if len(result)>=256:raise Error("Too many light tracks")
                if distant:suns+=1
                if suns>1:raise Error("Light track profile supports one distant light")
                indices[identity]=len(result)
                result.append(Self(identity.copy(),distant))
            var index=indices[identity]
            if distant!=result[index].distant:raise Error("Light type changes in track")
            for j in range(2,9):
                var value=Float64(String(f[j]))
                if not isfinite(value) or (j>=6 and (value<0 or value>60000)):raise Error("Invalid light key value")
            var time=Float64(String(f[2]))
            var direction=Vec3(Float64(String(f[3])),Float64(String(f[4])),Float64(String(f[5])))
            var color=Vec3(Float64(String(f[6])),Float64(String(f[7])),Float64(String(f[8])))
            if abs(direction.length()-1)>.0001:raise Error("Light direction must be normalized")
            var size=len(result[index].samples)
            if time<0 or (size>0 and time<=result[index].samples[size-1].time):raise Error("Light key times must increase")
            if size>0 and direction.dot(result[index].samples[size-1].direction)<-.9999:raise Error("Antipodal light direction keys")
            result[index].samples.append(LightSample3D(time,direction,color))
        return result^
