"""Skeletons, clip sampling/blending and CPU skinning with four joint influences.

CPU skinning feeds persistent dynamic GPU meshes; morph animation remains usable.
"""
from .transform3d import Transform3D,Quaternion,Mat4
from .math3d import Vec3
from .math2d import Vec2
from .mesh import Mesh
from .meshio import load_mesh
from .scene3d import Scene3D,SceneNode
from std.math import isfinite,floor,acos,sin,sqrt
from .assetio import BinaryAsset,ASSET_SKELETON,ASSET_CLIP,ASSET_SKIN
from .durableio import read_bounded
from .spatial import Bounds3D
from .graphics3d import Graphics3D

@fieldwise_init
struct Joint(ImplicitlyCopyable,Movable):
    var parent: Int
    var bind: Transform3D
    var inverse_bind: Mat4

struct Skeleton(Copyable,Movable):
    var joints: List[Joint]
    def __init__(out self):self.joints=List[Joint]()
    def matrices(self,poses: List[Transform3D]) raises -> List[Mat4]:
        if len(poses)!=len(self.joints):raise Error("Skeleton pose size mismatch")
        var scene=Scene3D()
        for i in range(len(poses)):
            var node=SceneNode(String(i),poses[i])
            node.parent=self.joints[i].parent
            scene.nodes.append(node^)
        return scene.world_matrices()
    @staticmethod
    def load(path: String) raises -> Self:
        if path.endswith(".atlasskeletonb"):
            var source=BinaryAsset(path,ASSET_SKELETON)
            var skeleton=Self()
            var count=source.count(4096)
            source.require(count*212)
            for _ in range(count):
                var parent=source.integer()
                var v=List[Float64]()
                for _ in range(26):v.append(source.floating())
                var inverse=Mat4()
                for i in range(16):inverse.data[i]=v[i+10]
                skeleton.joints.append(Joint(parent,Transform3D(Vec3(v[0],v[1],v[2]),Quaternion(v[3],v[4],v[5],v[6]),Vec3(v[7],v[8],v[9])),inverse))
            source.finish()
            var pose=List[Transform3D]()
            for joint in skeleton.joints:pose.append(joint.bind)
            _=skeleton.matrices(pose)
            return skeleton^
        var source: String
        source=read_bounded(path)
        var lines=source.split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_SKELETON_1":raise Error("Unsupported skeleton")
        var skeleton=Self()
        for i in range(1,len(lines)):
            var f=String(lines[i]).split()
            if len(f)==0:continue
            if len(f)!=28 or Int(String(f[0]))!=len(skeleton.joints):raise Error("Invalid joint record")
            var v=List[Float64]()
            for j in range(2,28):
                var value=Float64(String(f[j]))
                if not isfinite(value):raise Error("Non-finite joint")
                v.append(value)
            var transform=Transform3D(Vec3(v[0],v[1],v[2]),Quaternion(v[3],v[4],v[5],v[6]),Vec3(v[7],v[8],v[9]))
            var inverse=Mat4()
            for j in range(16):inverse.data[j]=v[10+j]
            skeleton.joints.append(Joint(Int(String(f[1])),transform,inverse))
        var pose=List[Transform3D]()
        for joint in skeleton.joints:pose.append(joint.bind)
        _=skeleton.matrices(pose)
        return skeleton^

@fieldwise_init
struct PoseKey(ImplicitlyCopyable,Movable):
    var time: Float64
    var x: Float64
    var y: Float64
    var z: Float64
    var w: Float64

struct PoseTrack(Copyable,Movable):
    var joint: Int
    var channel: Int
    var step: Bool
    var cubic: Bool
    var keys: List[PoseKey]
    var incoming: List[PoseKey]
    var outgoing: List[PoseKey]
    def __init__(out self,joint: Int,channel: Int,step: Bool=False,cubic: Bool=False):
        self.joint=joint
        self.channel=channel
        self.step=step
        self.cubic=cubic
        self.keys=List[PoseKey]()
        self.incoming=List[PoseKey]()
        self.outgoing=List[PoseKey]()

def cubic_value(a: Float64,b: Float64,outgoing: Float64,incoming: Float64,t: Float64,duration: Float64) -> Float64:
    var square=t*t
    var cube=square*t
    return (2*cube-3*square+1)*a+(cube-2*square+t)*duration*outgoing+(-2*cube+3*square)*b+(cube-square)*duration*incoming

def slerp(a: Quaternion,b: Quaternion,t: Float64) -> Quaternion:
    var left=a.normalized()
    var right=b.normalized()
    var dot=left.x*right.x+left.y*right.y+left.z*right.z+left.w*right.w
    if dot<0:
        right=Quaternion(-right.x,-right.y,-right.z,-right.w)
        dot=-dot
    if dot>0.9995:return Quaternion.nlerp(left,right,t)
    var angle=acos(max(-1.0,min(1.0,dot)))
    var first=sin((1-t)*angle)/sin(angle)
    var second=sin(t*angle)/sin(angle)
    return Quaternion(left.x*first+right.x*second,left.y*first+right.y*second,left.z*first+right.z*second,left.w*first+right.w*second).normalized()

struct AnimationClip(Copyable,Movable):
    var tracks: List[PoseTrack]
    var duration: Float64
    def __init__(out self):
        self.tracks=List[PoseTrack]()
        self.duration=0
    def sample(self,skeleton: Skeleton,time: Float64,looping: Bool=True) raises -> List[Transform3D]:
        if not isfinite(time):raise Error("Non-finite animation time")
        var pose=List[Transform3D]()
        for joint in skeleton.joints:pose.append(joint.bind)
        var clock=max(0.0,time)
        if looping and self.duration>0:clock-=floor(clock/self.duration)*self.duration
        else:clock=min(clock,self.duration)
        for track in self.tracks:
            if track.joint<0 or track.joint>=len(pose) or len(track.keys)==0:raise Error("Invalid animation track")
            var first=0
            for i in range(1,len(track.keys)):
                if track.keys[i].time>clock:break
                first=i
            var second=min(first+1,len(track.keys)-1)
            var a=track.keys[first]
            var b=track.keys[second]
            var weight: Float64=0
            if not track.step and b.time>a.time:weight=max(0.0,min(1.0,(clock-a.time)/(b.time-a.time)))
            var v=Vec3(a.x*(1-weight)+b.x*weight,a.y*(1-weight)+b.y*weight,a.z*(1-weight)+b.z*weight)
            var rotation=slerp(Quaternion(a.x,a.y,a.z,a.w),Quaternion(b.x,b.y,b.z,b.w),weight)
            if track.cubic:
                if len(track.incoming)!=len(track.keys) or len(track.outgoing)!=len(track.keys) or len(track.keys)<2:raise Error("Invalid cubic tangents")
                var incoming=track.incoming[second]
                var outgoing=track.outgoing[first]
                var dt=b.time-a.time
                v=Vec3(cubic_value(a.x,b.x,outgoing.x,incoming.x,weight,dt),cubic_value(a.y,b.y,outgoing.y,incoming.y,weight,dt),cubic_value(a.z,b.z,outgoing.z,incoming.z,weight,dt))
                if track.channel==1:
                    var w=cubic_value(a.w,b.w,outgoing.w,incoming.w,weight,dt)
                    if v.dot(v)+w*w<1e-20:raise Error("Cubic animation produced a zero quaternion")
                    rotation=Quaternion(v.x,v.y,v.z,w).normalized()
            if track.channel==0:pose[track.joint].position=v
            elif track.channel==1:pose[track.joint].rotation=rotation
            elif track.channel==2:pose[track.joint].scale=v
            else:raise Error("Invalid animation channel")
        return pose^
    @staticmethod
    def load(path: String) raises -> Self:
        if path.endswith(".atlasclipb"):
            var source=BinaryAsset(path,ASSET_CLIP)
            var clip=Self()
            var count=source.count(16384)
            for _ in range(count):
                var joint=source.integer()
                var channel=source.integer()
                var step=source.uint(4)
                if channel<0 or channel>2 or step>2:raise Error("Invalid binary animation track")
                var track=PoseTrack(joint,channel,step==1,step==2)
                var keys=source.count(1000000)
                source.require(keys*(104 if track.cubic else 40))
                if track.cubic and keys<2:raise Error("Cubic track needs two keys")
                for i in range(keys):
                    var clock=source.floating()
                    if clock<0 or i>0 and clock<=track.keys[i-1].time:raise Error("Binary animation times must increase")
                    var x=source.floating()
                    var y=source.floating()
                    var z=source.floating()
                    var w=source.floating()
                    track.keys.append(PoseKey(clock,x,y,z,w))
                    if track.cubic:
                        for direction in range(2):
                            var tx=source.floating()
                            var ty=source.floating()
                            var tz=source.floating()
                            var tw=source.floating()
                            if direction==0:track.incoming.append(PoseKey(clock,tx,ty,tz,tw))
                            else:track.outgoing.append(PoseKey(clock,tx,ty,tz,tw))
                    clip.duration=max(clip.duration,clock)
                clip.tracks.append(track^)
            source.finish()
            return clip^
        var source: String
        source=read_bounded(path)
        var lines=source.split("\n")
        if len(lines)==0 or (String(lines[0])!="ATLAS_CLIP_1" and String(lines[0])!="ATLAS_CLIP_2"):raise Error("Unsupported animation clip")
        var version2=String(lines[0])=="ATLAS_CLIP_2"
        var clip=Self()
        for i in range(1,len(lines)):
            var f=String(lines[i]).split()
            if len(f)==0:continue
            if len(f)!=(17 if version2 else 9):raise Error("Invalid clip record")
            var track=Int(String(f[0]))
            var mode=Int(String(f[3]))
            if mode<0 or mode>(2 if version2 else 1):raise Error("Invalid animation interpolation")
            if track==len(clip.tracks):clip.tracks.append(PoseTrack(Int(String(f[1])),Int(String(f[2])),mode==1,mode==2))
            if track<0 or track>=len(clip.tracks):raise Error("Invalid clip track order")
            if clip.tracks[track].joint!=Int(String(f[1])) or clip.tracks[track].channel!=Int(String(f[2])) or clip.tracks[track].step!=(mode==1) or clip.tracks[track].cubic!=(mode==2):raise Error("Inconsistent animation track metadata")
            var values=List[Float64]()
            for j in range(4,9):
                var value=Float64(String(f[j]))
                if not isfinite(value):raise Error("Non-finite clip value")
                values.append(value)
            var keys=len(clip.tracks[track].keys)
            if values[0]<0 or (keys>0 and values[0]<=clip.tracks[track].keys[keys-1].time):raise Error("Animation key times must increase")
            clip.tracks[track].keys.append(PoseKey(values[0],values[1],values[2],values[3],values[4]))
            if mode==2:
                var tangent=List[Float64]()
                for j in range(9,17):
                    var value=Float64(String(f[j]))
                    if not isfinite(value):raise Error("Non-finite cubic tangent")
                    tangent.append(value)
                clip.tracks[track].incoming.append(PoseKey(values[0],tangent[0],tangent[1],tangent[2],tangent[3]))
                clip.tracks[track].outgoing.append(PoseKey(values[0],tangent[4],tangent[5],tangent[6],tangent[7]))
            clip.duration=max(clip.duration,values[0])
        for track in clip.tracks:
            if track.cubic and len(track.keys)<2:raise Error("Cubic track needs two keys")
        return clip^

def blend_pose(a: List[Transform3D],b: List[Transform3D],weight: Float64) raises -> List[Transform3D]:
    if len(a)!=len(b) or not isfinite(weight) or weight<0 or weight>1:raise Error("Invalid pose blend")
    var result=List[Transform3D]()
    for i in range(len(a)):
        result.append(Transform3D(a[i].position*(1-weight)+b[i].position*weight,slerp(a[i].rotation,b[i].rotation,weight),a[i].scale*(1-weight)+b[i].scale*weight))
    return result^

struct SkinnedMesh:
    var mesh: Mesh
    var joints: List[Int]
    var weights: List[Float64]
    var root: Int
    var bind_bounds: Bounds3D
    def __init__(out self,var mesh: Mesh) raises:
        var prepared=mesh.deform_morph(mesh.morph_weights) if len(mesh.morphs)>0 else mesh.copy()
        self.bind_bounds=Bounds3D(prepared.minimum,prepared.maximum)
        self.mesh=mesh^
        self.joints=List[Int]()
        self.weights=List[Float64]()
        self.root=-1
    def upload(self,device: Graphics3D) raises -> Int:
        var prepared=self.mesh.deform_morph(self.mesh.morph_weights) if len(self.mesh.morphs)>0 else self.mesh.copy()
        return device.upload(prepared)
    def deform(self,skeleton: Skeleton,pose: List[Transform3D]) raises -> Mesh:
        var shaped=self.mesh.deform_morph(self.mesh.morph_weights) if len(self.mesh.morphs)>0 else self.mesh.copy()
        var count=len(self.mesh.vertices)//8
        if len(self.joints)!=count*4 or len(self.weights)!=count*4:raise Error("Skin influence count mismatch")
        var matrices=skeleton.matrices(pose)
        var root_inverse=Mat4()
        if self.root>=0:
            if self.root>=len(matrices):raise Error("Invalid skin root")
            root_inverse=matrices[self.root].inverse()
        var skins=List[Mat4]()
        for i in range(len(matrices)):skins.append(root_inverse*matrices[i]*skeleton.joints[i].inverse_bind)
        var result=Mesh()
        for i in range(count):
            var offset=i*8
            var p=Vec3(Float64(shaped.vertices[offset]),Float64(shaped.vertices[offset+1]),Float64(shaped.vertices[offset+2]))
            var normal=Vec3(Float64(shaped.vertices[offset+3]),Float64(shaped.vertices[offset+4]),Float64(shaped.vertices[offset+5]))
            var position=Vec3(0,0,0)
            var n=Vec3(0,0,0)
            var sum: Float64=0
            for influence in range(4):
                var joint=self.joints[i*4+influence]
                var weight=self.weights[i*4+influence]
                if not isfinite(weight) or weight<0 or joint<0 or joint>=len(skins):raise Error("Invalid skin influence")
                if weight==0:continue
                position=position+skins[joint].point(p)*weight
                n=n+skins[joint].normal(normal)*weight
                sum+=weight
            if sum<1e-12:raise Error("Skin vertex has zero weight")
            _=result.vertex(position*(1/sum),n.unit(),Vec2(Float64(self.mesh.vertices[offset+6]),Float64(self.mesh.vertices[offset+7])))
        result.indices=self.mesh.indices.copy()
        result.colors=shaped.colors.copy()
        if len(shaped.tangents)>0:
            for i in range(count):
                var tangent=Vec3(Float64(shaped.tangents[i*4]),Float64(shaped.tangents[i*4+1]),Float64(shaped.tangents[i*4+2]))
                var direction=Vec3(0,0,0)
                for influence in range(4):
                    var joint=self.joints[i*4+influence]
                    direction=direction+skins[joint].direction(tangent)*self.weights[i*4+influence]
                direction=direction.unit()
                result.tangents.append(Float32(direction.x))
                result.tangents.append(Float32(direction.y))
                result.tangents.append(Float32(direction.z))
                result.tangents.append(shaped.tangents[i*4+3])
        result.validate()
        return result^
    def gpu_data(self,skeleton: Skeleton,pose: List[Transform3D]) raises -> List[Float32]:
        """Joint position/normal palettes and four influences per base vertex.

        Positions stay on the GPU. The supplied mesh must already include its
        default morph deformation, matching deform()'s CPU reference.
        """
        var count=len(self.mesh.vertices)//8
        if len(self.joints)!=count*4 or len(self.weights)!=count*4:raise Error("Skin influence count mismatch")
        var matrices=skeleton.matrices(pose)
        if len(matrices)<1 or len(matrices)>4096:raise Error("GPU skeleton joint limit exceeded")
        var root_inverse=Mat4()
        if self.root>=0:
            if self.root>=len(matrices):raise Error("Invalid skin root")
            root_inverse=matrices[self.root].inverse()
        var size=1+len(matrices)*32+count*8
        if size>4*1024*1024:raise Error("GPU skin draw exceeds 16 MiB budget")
        var data=List[Float32](capacity=size)
        data.append(Float32(len(matrices)))
        for i in range(len(matrices)):
            var skin=root_inverse*matrices[i]*skeleton.joints[i].inverse_bind
            var inverse=skin.inverse()
            for j in range(16):data.append(Float32(skin.data[j]))
            for column in range(4):
                for row in range(4):data.append(Float32(inverse.data[row*4+column]))
        for i in range(count):
            var sum: Float64=0
            for influence in range(4):
                var joint=self.joints[i*4+influence]
                var weight=self.weights[i*4+influence]
                if joint<0 or joint>=len(matrices) or weight<0 or not isfinite(weight):raise Error("Invalid skin influence")
                data.append(Float32(joint))
                data.append(Float32(weight))
                sum+=weight
            if sum<1e-12:raise Error("Skin vertex has zero weight")
        return data^
    def gpu_bounds(self,palette: List[Float32]) raises -> Bounds3D:
        """Conservative union of joint-transformed bind bounds, including morphs.

        Nonnegative normalized skin weights are convex combinations, so every
        deformed position lies inside this union. Compute from the same palette
        used by the draw, then transform/cull independently for each pass.
        """
        if len(palette)<33 or not isfinite(palette[0]) or palette[0]<1 or palette[0]>4096:raise Error("Invalid skin palette bounds")
        var count=Int(palette[0])
        if count<1 or count>4096 or len(palette)<1+count*32:raise Error("Invalid skin palette bounds")
        var result=self.bind_bounds
        for joint in range(count):
            var matrix=Mat4()
            for i in range(16):
                var value=Float64(palette[1+joint*32+i])
                if not isfinite(value):raise Error("Non-finite skin palette")
                matrix.data[i]=value
            var bounds=self.bind_bounds.transformed(matrix)
            if joint==0:result=bounds
            else:
                result.minimum=Vec3(min(result.minimum.x,bounds.minimum.x),min(result.minimum.y,bounds.minimum.y),min(result.minimum.z,bounds.minimum.z))
                result.maximum=Vec3(max(result.maximum.x,bounds.maximum.x),max(result.maximum.y,bounds.maximum.y),max(result.maximum.z,bounds.maximum.z))
        var margin=(result.maximum-result.minimum).length()*.00001+.00001
        result.minimum=result.minimum-Vec3(margin,margin,margin)
        result.maximum=result.maximum+Vec3(margin,margin,margin)
        return result
    @staticmethod
    def load(mesh_path: String,skin_path: String) raises -> Self:
        var skin=Self(load_mesh(mesh_path))
        if skin_path.endswith(".atlasskinb"):
            var source=BinaryAsset(skin_path,ASSET_SKIN)
            source.validate_dependencies(skin_path)
            skin.root=source.integer()
            var count=source.count(2000000)
            if count!=len(skin.mesh.vertices)//8:raise Error("Binary skin vertex count mismatch")
            source.require(count*48)
            for _ in range(count):
                for _ in range(4):skin.joints.append(source.integer())
                for _ in range(4):
                    var weight=source.floating()
                    if weight<0:raise Error("Negative binary skin weight")
                    skin.weights.append(weight)
            source.finish()
            return skin^
        var source: String
        source=read_bounded(skin_path)
        var lines=source.split("\n")
        if len(lines)<2 or String(lines[0])!="ATLAS_SKIN_1":raise Error("Unsupported skin")
        skin.root=Int(String(lines[1]))
        for i in range(2,len(lines)):
            var f=String(lines[i]).split()
            if len(f)==0:continue
            if len(f)!=8:raise Error("Invalid skin record")
            for j in range(4):skin.joints.append(Int(String(f[j])))
            for j in range(4,8):skin.weights.append(Float64(String(f[j])))
        return skin^
