"""Sparse terrain authoring on a global lattice, shared by meshes and collision.

Snapshots are owned values: workers never read a layer being edited. The reserved
world cell is committed with ordinary object cells by the same redo transaction.
"""
from std.collections import Dict
from std.math import isfinite, sqrt
from .math3d import Vec3
from .scene3d import Scene3D,SceneNode,Material
from .transform3d import Transform3D

comptime TERRAIN_CELL = Int.MIN

@fieldwise_init
struct TerrainSample(ImplicitlyCopyable,Movable):
    var height: Float64
    var color: Vec3

@fieldwise_init
struct TerrainChange(ImplicitlyCopyable,Movable):
    var x: Int
    var z: Int
    var existed: Bool
    var before: TerrainSample
    var after: TerrainSample

def terrain_key(x: Int,z: Int) -> String:return String(x)+":"+String(z)
def default_sample() -> TerrainSample:return TerrainSample(0,Vec3(.22,.36,.14))

struct TerrainLayer(Copyable,Movable):
    var spacing: Float64
    var samples: Dict[String,TerrainSample]
    var min_delta: Float64
    var max_delta: Float64
    var has_paint: Bool
    def __init__(out self,spacing: Float64=2) raises:
        if not isfinite(spacing) or spacing<.25 or spacing>64:raise Error("Invalid terrain authoring spacing")
        self.spacing=spacing
        self.samples=Dict[String,TerrainSample]()
        self.min_delta=0
        self.max_delta=0
        self.has_paint=False
    def memory_bytes(self) -> Int:return len(self.samples)*256+4096
    def get(self,x: Int,z: Int) -> TerrainSample:return self.samples.get(terrain_key(x,z),default_sample())
    def sample(self,x: Float64,z: Float64) -> TerrainSample:
        if len(self.samples)==0:return default_sample()
        if not isfinite(x) or not isfinite(z) or abs(x/self.spacing)>Float64(1<<40) or abs(z/self.spacing)>Float64(1<<40):return default_sample()
        var gx=x/self.spacing
        var gz=z/self.spacing
        var ix=Int(gx//1)
        var iz=Int(gz//1)
        var fx=gx-Float64(ix)
        var fz=gz-Float64(iz)
        var a=self.get(ix,iz)
        var b=self.get(ix+1,iz)
        var c=self.get(ix,iz+1)
        var d=self.get(ix+1,iz+1)
        return TerrainSample((a.height*(1-fx)+b.height*fx)*(1-fz)+(c.height*(1-fx)+d.height*fx)*fz,(a.color*(1-fx)+b.color*fx)*(1-fz)+(c.color*(1-fx)+d.color*fx)*fz)
    def refresh(mut self) raises:
        self.min_delta=0
        self.max_delta=0
        self.has_paint=False
        for key in self.samples:
            var value=self.samples[key]
            self.min_delta=min(self.min_delta,value.height)
            self.max_delta=max(self.max_delta,value.height)
            if (value.color-default_sample().color).length()>1e-8:self.has_paint=True
    def brush(self,center: Vec3,radius: Float64,amount: Float64,color: Vec3=Vec3(.22,.36,.14),paint: Bool=False) raises -> List[TerrainChange]:
        if not isfinite(center.x) or not isfinite(center.z) or abs(center.x/self.spacing)>Float64((1<<40)-1024) or abs(center.z/self.spacing)>Float64((1<<40)-1024) or not isfinite(radius) or radius<self.spacing*.5 or radius>128 or not isfinite(amount) or abs(amount)>64:raise Error("Invalid terrain brush")
        if paint and (amount<0 or amount>1 or not isfinite(color.x) or not isfinite(color.y) or not isfinite(color.z) or min(color.x,min(color.y,color.z))<0 or max(color.x,max(color.y,color.z))>1):raise Error("Invalid terrain paint")
        var changes=List[TerrainChange]()
        var added=0
        for z in range(Int((center.z-radius)//self.spacing),Int((center.z+radius)//self.spacing)+1):
            for x in range(Int((center.x-radius)//self.spacing),Int((center.x+radius)//self.spacing)+1):
                var dx=Float64(x)*self.spacing-center.x
                var dz=Float64(z)*self.spacing-center.z
                var distance=sqrt(dx*dx+dz*dz)
                if distance>=radius:continue
                if len(changes)>=16384:raise Error("Terrain stroke exceeds sample budget")
                var weight=1-distance/radius
                weight=weight*weight*(3-2*weight)
                var before=self.get(x,z)
                var after=before
                if paint:after.color=before.color*(1-amount*weight)+color*(amount*weight)
                else:after.height=max(Float64(-1024),min(Float64(1024),before.height+amount*weight))
                var existed=terrain_key(x,z) in self.samples
                if not existed:added+=1
                changes.append(TerrainChange(x,z,existed,before,after))
        if len(self.samples)+added>65536:raise Error("Terrain layer exceeds sample budget")
        return changes^
    def apply(mut self,changes: List[TerrainChange],reverse: Bool=False) raises:
        # Publish only after every coordinate/value and the total size validates.
        if len(changes)>65536:raise Error("Terrain command exceeds sample budget")
        var candidate=self.samples.copy()
        for index in range(len(changes)):
            var change=changes[len(changes)-1-index if reverse else index]
            var key=terrain_key(change.x,change.z)
            var value=change.before if reverse else change.after
            if abs(change.x)>1<<40 or abs(change.z)>1<<40 or not isfinite(value.height) or abs(value.height)>1024 or not isfinite(value.color.x) or not isfinite(value.color.y) or not isfinite(value.color.z) or min(value.color.x,min(value.color.y,value.color.z))<0 or max(value.color.x,max(value.color.y,value.color.z))>1:raise Error("Invalid terrain sample")
            if reverse and not change.existed:
                if key in candidate:_=candidate.pop(key)
            else:candidate[key]=value
        if len(candidate)>65536:raise Error("Terrain layer exceeds sample budget")
        self.samples=candidate^
        self.refresh()
    def scene(self) raises -> Scene3D:
        var scene=Scene3D()
        scene.nodes.append(SceneNode("ATLAS_TERRAIN_1",Transform3D(Vec3(self.spacing,0,0)),persistent_id="terrain:config"))
        for key in self.samples:
            var parts=key.split(":")
            # Keys originate only in validated lattice coordinates.
            var x=Int(String(parts[0]))
            var z=Int(String(parts[1]))
            var value=self.samples[key]
            scene.nodes.append(SceneNode(key.copy(),Transform3D(Vec3(Float64(x),value.height,Float64(z))),material=Material(value.color),persistent_id="terrain:"+key))
        return scene^
    @staticmethod
    def from_scene(scene: Scene3D) raises -> Self:
        if len(scene.nodes)<1 or len(scene.nodes)>65537 or scene.nodes[0].name!="ATLAS_TERRAIN_1" or scene.nodes[0].persistent_id!="terrain:config":raise Error("Invalid terrain layer header")
        var layer=Self(scene.nodes[0].transform.position.x)
        for i in range(len(scene.nodes)):
            ref node=scene.nodes[i]
            if not node.active or node.parent!=-1 or node.mesh!=-1 or node.asset_key.byte_length()>0 or node.material_key.byte_length()>0 or node.material.texture!=-1 or node.transform.rotation.x!=0 or node.transform.rotation.y!=0 or node.transform.rotation.z!=0 or node.transform.rotation.w!=1 or (node.transform.scale.x!=1 or node.transform.scale.y!=1 or node.transform.scale.z!=1):raise Error("Invalid terrain layer record")
            if i==0:continue
            var point=node.transform.position
            if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z) or abs(point.x)>Float64(1<<40) or abs(point.z)>Float64(1<<40) or abs(point.y)>1024:raise Error("Terrain sample exceeds bounds")
            var x=Int(point.x)
            var z=Int(point.z)
            var key=terrain_key(x,z)
            var color=node.material.color
            if not isfinite(color.x) or not isfinite(color.y) or not isfinite(color.z) or Float64(x)!=point.x or Float64(z)!=point.z or key!=node.name or node.persistent_id!="terrain:"+key or key in layer.samples or min(color.x,min(color.y,color.z))<0 or max(color.x,max(color.y,color.z))>1:raise Error("Invalid terrain sample identity or color")
            layer.samples[key]=TerrainSample(point.y,color)
        layer.refresh()
        return layer^
