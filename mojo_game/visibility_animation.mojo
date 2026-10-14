"""Composed USD visibility uses held keys and filters draws without deleting nodes."""
from std.math import isfinite
from std.collections import Dict
from .durableio import read_bounded

@fieldwise_init
struct VisibilityKey(ImplicitlyCopyable,Movable):
    var time: Float64
    var visible: Bool

struct VisibilityTrack(Copyable,Movable):
    var asset: String
    var keys: List[VisibilityKey]
    def __init__(out self,var asset: String):
        self.asset=asset^
        self.keys=List[VisibilityKey]()
    def sample(self,time: Float64) raises -> Bool:
        if not isfinite(time) or len(self.keys)==0:raise Error("Invalid visibility sample")
        var low=0
        var high=len(self.keys)-1
        while low<high:
            var mid=(low+high+1)//2
            if self.keys[mid].time<=time:low=mid
            else:high=mid-1
        return self.keys[low].visible
    @staticmethod
    def hidden(tracks: List[Self],time: Float64) raises -> Dict[String,Bool]:
        var result=Dict[String,Bool]()
        for track in tracks:result[track.asset]=not track.sample(time)
        return result^
    @staticmethod
    def load(path: String) raises -> List[Self]:
        var rows=read_bounded(path,32*1024*1024).split("\n")
        if len(rows)==0 or String(rows[0])!="ATLAS_VISIBILITY_1":raise Error("Invalid visibility format")
        var result=List[Self]()
        var indices=Dict[String,Int]()
        var count=0
        for i in range(1,len(rows)):
            if String(rows[i]).byte_length()==0:continue
            var f=String(rows[i]).split("\t")
            if len(f)!=3:raise Error("Invalid visibility row")
            var asset=String(f[0])
            var time=Float64(String(f[1]))
            var visible=Int(String(f[2]))
            count+=1
            if asset.byte_length()==0 or asset.byte_length()>4096 or not isfinite(time) or time<0 or visible<0 or visible>1 or count>100000:raise Error("Invalid visibility key")
            if asset not in indices:
                if len(result)>=4096:raise Error("Too many visibility tracks")
                indices[asset]=len(result)
                result.append(Self(asset.copy()))
            var index=indices[asset]
            var n=len(result[index].keys)
            if n>=10001 or (n>0 and time<=result[index].keys[n-1].time):raise Error("Invalid visibility key order or count")
            result[index].keys.append(VisibilityKey(time,visible==1))
        return result^
