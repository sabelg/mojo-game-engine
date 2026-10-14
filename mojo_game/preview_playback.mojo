"""Bounded cooked-scene playback for the USD inspection viewport.

The scene export's exported scene clips drive node TRS, CPU skinning and morph weights.
This is an inspection path, not a frame-budget guarantee for production crowds.
"""
from std.collections import Dict
from .skeletal import Skeleton,Joint,AnimationClip,SkinnedMesh
from .morph_animation import MorphTrack
from .mesh import Mesh
from .meshio import load_mesh
from .scene3d import Scene3D
from .assets3d import Assets3D
from .graphics3d import Graphics3D
from .transform3d import Transform3D,Mat4
from .spatial import Bounds3D
from .durableio import read_bounded,exists
from .assetio import validate_asset_path

struct PreviewPlayback:
    var bind: Skeleton
    var clip: AnimationClip
    var weights: List[MorphTrack]
    var skins: List[SkinnedMesh]
    var skeletons: List[Skeleton]
    var skin_assets: List[Int]
    var morphs: List[Mesh]
    var morph_assets: List[Int]
    var duration: Float64
    var last_time: Float64
    def __init__(out self):
        self.bind=Skeleton()
        self.clip=AnimationClip()
        self.weights=List[MorphTrack]()
        self.skins=List[SkinnedMesh]()
        self.skeletons=List[Skeleton]()
        self.skin_assets=List[Int]()
        self.morphs=List[Mesh]()
        self.morph_assets=List[Int]()
        self.duration=0
        self.last_time = -1

    @staticmethod
    def load(prefix: String,scene: Scene3D,assets: Assets3D) raises -> Self:
        var result=Self()
        for node in scene.nodes:result.bind.joints.append(Joint(node.parent,node.transform,Mat4()))
        if not exists(prefix+"-playback.atlasplayback"):return result^
        var parent=String(".")
        for i in range(prefix.byte_length()-1,-1,-1):
            if String(prefix[byte=i])=="/":parent=String(prefix[byte=:i]);break
        var lines=read_bounded(prefix+"-playback.atlasplayback",1024*1024).split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_PLAYBACK_1":raise Error("Invalid playback manifest")
        var seen=Dict[String,Bool]()
        var vertices=0
        var channels=Dict[String,Bool]()
        var morph_channels=Dict[String,Bool]()
        for i in range(1,len(lines)):
            var f=String(lines[i]).split("\t")
            if String(f[0]).byte_length()==0:continue
            var kind=String(f[0])
            if (kind=="clip" or kind=="weights") and len(f)==2:
                validate_asset_path(String(f[1]))
                if kind=="clip":
                    var clip=AnimationClip.load(parent+"/"+String(f[1]))
                    result.clip.duration=max(result.clip.duration,clip.duration)
                    for track in clip.tracks:
                        var channel=String(track.joint)+":"+String(track.channel)
                        if channel in channels:raise Error("Overlapping scene clip channels")
                        channels[channel]=True
                        result.clip.tracks.append(track.copy())
                    result.duration=max(result.duration,result.clip.duration)
                else:
                    var tracks=MorphTrack.load(parent+"/"+String(f[1]))
                    for track in tracks:
                        if track.asset in morph_channels:raise Error("Overlapping scene morph clips")
                        morph_channels[track.asset]=True
                        result.duration=max(result.duration,track.keys[len(track.keys)-1].time)
                        result.weights.append(track.copy())
            elif (kind=="skin" and len(f)==5) or (kind=="morph" and len(f)==3):
                var key=String(f[1])
                if key in seen or len(seen)>=4096:raise Error("Duplicate deformation asset or budget exceeded")
                seen[key]=True
                var index=assets.find(key)
                if index<0:raise Error("Unknown deformation asset")
                for j in range(2,len(f)):validate_asset_path(String(f[j]))
                if kind=="skin":
                    var skin=SkinnedMesh.load(parent+"/"+String(f[2]),parent+"/"+String(f[3]))
                    vertices+=len(skin.mesh.vertices)//8
                    result.skins.append(skin^)
                    result.skeletons.append(Skeleton.load(parent+"/"+String(f[4])))
                    result.skin_assets.append(index)
                else:
                    var mesh=load_mesh(parent+"/"+String(f[2]))
                    vertices+=len(mesh.vertices)//8
                    result.morphs.append(mesh^)
                    result.morph_assets.append(index)
                if vertices>250000:raise Error("Preview CPU deformation exceeds 250000 vertices")
            else:raise Error("Invalid playback record")
        for track in result.weights:
            if track.asset not in seen:raise Error("Morph track has no deformation asset")
        _=result.clip.sample(result.bind,0,False)
        return result^

    def apply(mut self,device: Graphics3D,mut assets: Assets3D,time: Float64) raises -> Dict[Int,Transform3D]:
        var pose=self.clip.sample(self.bind,time,False)
        var overrides=Dict[Int,Transform3D]()
        for i in range(len(pose)):overrides[i]=pose[i]
        if time==self.last_time:return overrides^
        var prepared=List[Mesh]()
        var targets=List[Int]()
        for i in range(len(self.skins)):
            var key=assets.keys[self.skin_assets[i]].copy()
            for track in self.weights:
                if track.asset==key:self.skins[i].mesh.morph_weights=track.sample(time)
            var skin_pose=self.clip.sample(self.skeletons[i],time,False)
            prepared.append(self.skins[i].deform(self.skeletons[i],skin_pose))
            targets.append(self.skin_assets[i])
        for i in range(len(self.morphs)):
            var weights=self.morphs[i].morph_weights.copy()
            var key=assets.keys[self.morph_assets[i]].copy()
            for track in self.weights:
                if track.asset==key:weights=track.sample(time)
            prepared.append(self.morphs[i].deform_morph(weights))
            targets.append(self.morph_assets[i])
        for i in range(len(prepared)):
            device.update_mesh(assets.handles[targets[i]],prepared[i])
            assets.bounds[targets[i]]=Bounds3D(prepared[i].minimum,prepared[i].maximum)
        self.last_time=time
        return overrides^
