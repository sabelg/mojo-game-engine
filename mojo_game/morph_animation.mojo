"""Bounded morph animation tracks. CPU deformation precedes skeletal skinning.

Weights retain glTF LINEAR, STEP and CUBICSPLINE interpolation without clamping.
Use sample() with Mesh.deform_morph(), or assign SkinnedMesh.mesh.morph_weights
before deforming a skeleton. GPU morph execution is not provided by this module.
"""
from std.math import isfinite
from std.collections import Dict
from .durableio import read_bounded

struct MorphKey(Copyable,Movable):
    var time: Float64
    var values: List[Float64]
    def __init__(out self,time: Float64,var values: List[Float64]):
        self.time=time
        self.values=values^

struct MorphTrack(Copyable,Movable):
    var asset: String
    var width: Int
    var mode: Int
    var keys: List[MorphKey]
    def __init__(out self,var asset: String,width: Int,mode: Int):
        self.asset=asset^
        self.width=width
        self.mode=mode
        self.keys=List[MorphKey]()

    def sample(self,time: Float64) raises -> List[Float64]:
        if not isfinite(time) or len(self.keys)==0:raise Error("Invalid morph sample time or empty track")
        var low=0
        var high=len(self.keys)-1
        while low<high:
            var mid=(low+high+1)//2
            if self.keys[mid].time<=time:low=mid
            else:high=mid-1
        var next=min(low+1,len(self.keys)-1)
        var a=self.keys[low].copy()
        var b=self.keys[next].copy()
        var duration=b.time-a.time
        var t: Float64=0
        if duration>0:t=max(0.0,min(1.0,(time-a.time)/duration))
        if time<=self.keys[0].time:t=0
        var result=List[Float64]()
        for i in range(self.width):
            var value: Float64
            if self.mode==0:value=a.values[i]*(1-t)+b.values[i]*t
            elif self.mode==1:value=a.values[i]
            else:
                var t2=t*t
                var t3=t2*t
                value=(2*t3-3*t2+1)*a.values[self.width+i]+(t3-2*t2+t)*duration*a.values[2*self.width+i]+(-2*t3+3*t2)*b.values[self.width+i]+(t3-t2)*duration*b.values[i]
            if not isfinite(value):raise Error("Morph interpolation overflow")
            result.append(value)
        return result^

    @staticmethod
    def load(path: String) raises -> List[Self]:
        var lines=read_bounded(path,32*1024*1024).split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_MORPH_CLIP_1":raise Error("Unsupported morph clip")
        var result=List[Self]()
        var tracks=Dict[String,Int]()
        var count=0
        for i in range(1,len(lines)):
            if String(lines[i]).byte_length()==0:continue
            var f=String(lines[i]).split("\t")
            if len(f)<5:raise Error("Invalid morph record")
            var asset=String(f[0])
            var mode=Int(String(f[1]))
            var width=Int(String(f[2]))
            var clock=Float64(String(f[3]))
            if asset.byte_length()==0 or asset.byte_length()>4096 or mode<0 or mode>2 or width<1 or width>64 or not isfinite(clock) or clock<0:raise Error("Invalid morph metadata")
            if len(f)!=4+width*(3 if mode==2 else 1):raise Error("Invalid morph record width")
            count+=1
            if count>100000:raise Error("Morph clip exceeds key budget")
            if asset not in tracks:
                if len(result)>=4096:raise Error("Morph clip exceeds track budget")
                tracks[asset]=len(result)
                result.append(Self(asset.copy(),width,mode))
            var index=tracks[asset]
            var n=len(result[index].keys)
            if result[index].mode!=mode or result[index].width!=width or n>=10000:raise Error("Inconsistent morph track or key budget")
            if n>0 and clock<=result[index].keys[n-1].time:raise Error("Morph times must strictly increase")
            var values=List[Float64]()
            for j in range(4,len(f)):
                var value=Float64(String(f[j]))
                if not isfinite(value):raise Error("Non-finite morph weight")
                values.append(value)
            result[index].keys.append(MorphKey(clock,values^))
        for track in result:
            if track.mode==2 and len(track.keys)<2:raise Error("Cubic morph track needs two keys")
        return result^
