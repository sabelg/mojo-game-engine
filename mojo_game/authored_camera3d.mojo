"""Cooked USD camera samples in metres/Y-up, ready for Graphics3D.begin.

Cameras retain their authored aperture aspect; the caller chooses a matching
viewport or letterboxes it. Camera tracks interpolate baked per-frame samples.
"""
from std.math import isfinite
from std.collections import Dict
from .math3d import Vec3
from .transform3d import Mat4,Quaternion,Transform3D
from .durableio import read_bounded

struct AuthoredCamera3D(Copyable, Movable):
    var identity: String
    var world: Mat4
    var projection: Mat4
    var exposure: Float64

    def __init__(out self, var identity: String, world: Mat4, projection: Mat4, exposure: Float64=1) raises:
        if identity.byte_length()==0 or identity.byte_length()>4096:raise Error("Invalid camera identity")
        for value in world.data:
            if not isfinite(value):raise Error("Non-finite camera transform")
        for value in projection.data:
            if not isfinite(value):raise Error("Non-finite camera projection")
        if world.data[3]!=0 or world.data[7]!=0 or world.data[11]!=0 or world.data[15]!=1:raise Error("Non-affine camera transform")
        _=world.inverse()
        _=projection.inverse()
        if not isfinite(exposure) or exposure<0 or exposure>1000000:raise Error("Invalid camera exposure scale")
        self.identity=identity^
        self.world=world
        self.projection=projection
        self.exposure=exposure

    def position(self) -> Vec3:
        return Vec3(self.world.data[12],self.world.data[13],self.world.data[14])

    def view(self, origin: Vec3=Vec3(0,0,0)) raises -> Mat4:
        var relative=self.world
        relative.data[12]-=origin.x
        relative.data[13]-=origin.y
        relative.data[14]-=origin.z
        return relative.inverse()

    def view_projection(self, origin: Vec3=Vec3(0,0,0)) raises -> Mat4:
        return self.projection*self.view(origin)

    @staticmethod
    def load(path: String) raises -> List[Self]:
        var lines=read_bounded(path,1024*1024).split("\n")
        if len(lines)==0 or (String(lines[0])!="ATLAS_CAMERAS_1" and String(lines[0])!="ATLAS_CAMERAS_2"):raise Error("Unsupported camera format")
        var result=List[Self]()
        var version2=String(lines[0])=="ATLAS_CAMERAS_2"
        var identities=Dict[String,Bool]()
        for i in range(1,len(lines)):
            if String(lines[i]).byte_length()==0:continue
            var fields=String(lines[i]).split("\t")
            if len(fields)!=(34 if version2 else 33) or len(result)>=256:raise Error("Invalid camera record or camera budget")
            var identity=String(fields[0])
            if identity in identities:raise Error("Duplicate camera identity")
            identities[identity]=True
            var world=Mat4()
            var projection=Mat4()
            for j in range(16):
                world.data[j]=Float64(String(fields[1+j]))
                projection.data[j]=Float64(String(fields[17+j]))
            result.append(Self(identity^,world,projection,Float64(String(fields[33])) if version2 else 1))
        return result^

struct CameraSample3D(ImplicitlyCopyable, Movable):
    var time: Float64
    var position: Vec3
    var rotation: Quaternion
    var projection: Mat4
    var exposure: Float64

    def __init__(out self,time: Float64,position: Vec3,rotation: Quaternion,projection: Mat4,exposure: Float64=1):
        self.time=time
        self.position=position
        self.rotation=rotation
        self.projection=projection
        self.exposure=exposure

struct AuthoredCameraTrack3D(Copyable, Movable):
    var identity: String
    var samples: List[CameraSample3D]

    def __init__(out self,var identity: String):
        self.identity=identity^
        self.samples=List[CameraSample3D]()

    def sample(self,time: Float64) raises -> AuthoredCamera3D:
        if not isfinite(time) or len(self.samples)==0:raise Error("Invalid camera sample request")
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
        var position=a.position*(1-t)+b.position*t
        var rotation=Quaternion.nlerp(a.rotation,b.rotation,t)
        var projection=Mat4()
        for i in range(16):projection.data[i]=a.projection.data[i]*(1-t)+b.projection.data[i]*t
        return AuthoredCamera3D(self.identity.copy(),Transform3D(position,rotation).matrix(),projection,a.exposure*(1-t)+b.exposure*t)

    @staticmethod
    def load(path: String) raises -> List[Self]:
        var lines=read_bounded(path,32*1024*1024).split("\n")
        if len(lines)==0 or (String(lines[0])!="ATLAS_CAMERA_TRACKS_1" and String(lines[0])!="ATLAS_CAMERA_TRACKS_2"):raise Error("Unsupported camera track format")
        var result=List[Self]()
        var version2=String(lines[0])=="ATLAS_CAMERA_TRACKS_2"
        var indices=Dict[String,Int]()
        var count=0
        for i in range(1,len(lines)):
            if String(lines[i]).byte_length()==0:continue
            count+=1
            var fields=String(lines[i]).split("\t")
            if count>16384 or len(fields)!=(26 if version2 else 25):raise Error("Camera animation exceeds sample budget or has invalid record")
            var identity=String(fields[0])
            if identity.byte_length()==0 or identity.byte_length()>4096:raise Error("Invalid camera track identity")
            if identity not in indices:
                if len(result)>=256:raise Error("Camera track count exceeds 256")
                indices[identity]=len(result)
                result.append(Self(identity.copy()))
            var index=indices[identity]
            for j in range(1,25):
                if not isfinite(Float64(String(fields[j]))):raise Error("Non-finite camera key")
            var time=Float64(String(fields[1]))
            var size=len(result[index].samples)
            if time<0 or (size>0 and time<=result[index].samples[size-1].time):raise Error("Camera key times must increase")
            var position=Vec3(Float64(String(fields[2])),Float64(String(fields[3])),Float64(String(fields[4])))
            var q=Quaternion(Float64(String(fields[5])),Float64(String(fields[6])),Float64(String(fields[7])),Float64(String(fields[8])))
            if abs(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w-1)>.0001:raise Error("Camera quaternion must be normalized")
            var projection=Mat4()
            for j in range(16):projection.data[j]=Float64(String(fields[9+j]))
            _=projection.inverse()
            var exposure=Float64(String(fields[25])) if version2 else Float64(1)
            if not isfinite(exposure) or exposure<0 or exposure>1000000:raise Error("Invalid camera key exposure scale")
            result[index].samples.append(CameraSample3D(time,position,q,projection,exposure))
        return result^
