"""Cooked static hierarchy aggregation with conservative bounds and safe fallback.

One HLOD3D belongs to one scene. Change scene revision after any authored edit.
Assets own the proxy handles. Wind-driven foliage uses ordinary instancing instead
of these world-baked static proxies; draw_lod_instances supports its transitions.
"""
from std.collections import Dict
from .assetio import BinaryAsset
from .assets3d import Assets3D
from .scene3d import Scene3D,Material
from .visibility3d import SceneDrawCache
from .math3d import Vec3
from .transform3d import Mat4,Transform3D
from .spatial import Bounds3D,Frustum
from .graphics3d import Graphics3D
from std.math import isfinite

@fieldwise_init
struct HLODSource3D(Copyable,Movable):
    var identity: String
    var asset: String
    var matrix: Mat4

struct HLODCluster3D(Copyable,Movable):
    var center: Vec3
    var bounds: Bounds3D
    var distance: Float64
    var width: Float64
    var error: Float64
    var material_key: String
    var material: Material
    var proxy: Int
    var sources: List[HLODSource3D]
    def __init__(out self):
        self.center=Vec3(0,0,0)
        self.bounds=Bounds3D(Vec3(0,0,0),Vec3(0,0,0))
        self.distance=1;self.width=0;self.error=0
        self.material_key=String();self.material=Material();self.proxy=-1
        self.sources=List[HLODSource3D]()

@fieldwise_init
struct HLODBatch3D(Copyable,Movable):
    var mesh: Int
    var material: Material
    var matrices: List[Mat4]
    var threshold: Float64

def hlod_material_equal(a: Material,b: Material) -> Bool:
    return a.color.x==b.color.x and a.color.y==b.color.y and a.color.z==b.color.z and a.roughness==b.roughness and a.metallic==b.metallic and a.emission==b.emission and a.texture==b.texture

struct HLOD3D:
    var clusters: List[HLODCluster3D]
    var cache: SceneDrawCache
    var membership: Dict[Int,Int]
    var valid: List[Bool]
    var asset_revision: UInt64
    var prepared_revision: Int
    var prepared_assets: UInt64
    var prepared_nodes: Int
    var enabled: Bool
    var transitions: Bool

    def __init__(out self,path: String,assets: Assets3D) raises:
        self.clusters=List[HLODCluster3D]()
        self.cache=SceneDrawCache()
        self.membership=Dict[Int,Int]()
        self.valid=List[Bool]()
        self.asset_revision=assets.revision
        self.prepared_revision=-1;self.prepared_assets=0;self.prepared_nodes=-1
        self.enabled=True;self.transitions=True
        var binary=BinaryAsset(path,8)
        binary.validate_dependencies(path)
        var count=binary.count(4094)
        var seen=Dict[String,Bool]()
        var total=0
        for _ in range(count):
            var cluster=HLODCluster3D()
            cluster.center=Vec3(binary.floating(),binary.floating(),binary.floating())
            cluster.bounds=Bounds3D(Vec3(binary.floating(),binary.floating(),binary.floating()),Vec3(binary.floating(),binary.floating(),binary.floating()))
            cluster.distance=binary.floating();cluster.width=binary.floating();cluster.error=binary.floating()
            var color=Vec3(binary.floating(),binary.floating(),binary.floating())
            cluster.material=Material(color,binary.floating(),binary.floating(),binary.floating())
            cluster.material_key=binary.identifier()
            var proxy=binary.identifier()
            var proxy_hash=binary.uint(8)
            cluster.proxy=assets.find(proxy)
            if assets.checksums.get(proxy,0)!=proxy_hash:raise Error("HLOD proxy registry differs from cooked generation")
            if cluster.proxy<0 or cluster.material_key.byte_length()>1024 or cluster.material_key.byte_length()>0 and cluster.material_key not in assets.materials:raise Error("HLOD references missing proxy/material")
            if cluster.material_key.byte_length()>0:cluster.material=assets.materials[cluster.material_key]
            var low=cluster.bounds.minimum;var high=cluster.bounds.maximum;var center=cluster.center
            if low.x>high.x or low.y>high.y or low.z>high.z or center.x<low.x or center.x>high.x or center.y<low.y or center.y>high.y or center.z<low.z or center.z>high.z or cluster.distance<1 or cluster.distance>100000 or cluster.width<0 or cluster.width>cluster.distance or cluster.error<0 or cluster.error>16:raise Error("Invalid HLOD bounds or policy")
            var proxy_bounds=assets.bounds[cluster.proxy].transformed(Transform3D(center).matrix())
            var tolerance=Float64(.001)+cluster.error
            if proxy_bounds.minimum.x<low.x-tolerance or proxy_bounds.minimum.y<low.y-tolerance or proxy_bounds.minimum.z<low.z-tolerance or proxy_bounds.maximum.x>high.x+tolerance or proxy_bounds.maximum.y>high.y+tolerance or proxy_bounds.maximum.z>high.z+tolerance:raise Error("HLOD proxy exceeds its conservative bounds")
            var sources=binary.count(100000)
            total+=sources
            if sources<2 or total>100000:raise Error("HLOD source budget exceeded")
            for _ in range(sources):
                var identity=binary.identifier();var asset=binary.identifier();var asset_hash=binary.uint(8);var matrix=Mat4()
                if identity.byte_length()<1 or identity.byte_length()>64 or identity in seen or assets.find(asset)<0:raise Error("Invalid/duplicate HLOD source identity or asset")
                if assets.checksums.get(asset,0)!=asset_hash:raise Error("HLOD source registry differs from cooked generation")
                seen[identity]=True
                for i in range(16):matrix.data[i]=binary.floating()
                if matrix.data[3]!=0 or matrix.data[7]!=0 or matrix.data[11]!=0 or matrix.data[15]!=1:raise Error("Non-affine HLOD source transform")
                _=matrix.inverse()
                cluster.sources.append(HLODSource3D(identity^,asset^,matrix^))
            self.clusters.append(cluster^)
            self.valid.append(False)
        binary.finish()

    def prepare(mut self,assets: Assets3D,scene: Scene3D,revision: Int) raises:
        assets.prepare_scene(scene,self.cache,revision)
        if self.prepared_revision==revision and self.prepared_assets==assets.revision and self.prepared_nodes==len(scene.nodes):return
        self.membership.clear()
        var identities=Dict[String,Int]()
        for i in range(len(scene.nodes)):
            if not scene.valid(i):continue
            var identity=scene.nodes[i].persistent_id.copy()
            if identity in identities:raise Error("Duplicate authored identity in HLOD scene")
            identities[identity^]=i
        var matrices=scene.world_matrices()
        for i in range(len(self.clusters)):
            ref cluster=self.clusters[i]
            var valid=assets.revision==self.asset_revision
            for source in cluster.sources:
                if source.identity not in identities:
                    valid=False
                    continue
                var node=identities[source.identity]
                if scene.nodes[node].asset_key!=source.asset or scene.nodes[node].material_key!=cluster.material_key or cluster.material_key.byte_length()==0 and not hlod_material_equal(scene.nodes[node].material,cluster.material):valid=False
                for j in range(16):
                    if abs(matrices[node].data[j]-source.matrix.data[j])>(Float64(1e-7) if j>=12 else Float64(1e-10)*max(Float64(1),abs(source.matrix.data[j]))):valid=False
            self.valid[i]=valid
            if valid:
                for source in cluster.sources:self.membership[identities[source.identity]]=i
        self.prepared_revision=revision;self.prepared_assets=assets.revision;self.prepared_nodes=len(scene.nodes)

    def draw(mut self,mut assets: Assets3D,device: Graphics3D,scene: Scene3D,revision: Int,camera: Vec3,origin: Vec3,view: Mat4,shadow: Bool=False) raises:
        for value in [camera.x,camera.y,camera.z]:
            if not isfinite(value):raise Error("Invalid HLOD camera")
        assets.collect(device)
        self.prepare(assets,scene,revision)
        var thresholds=List[Float64]()
        var frustum=Frustum(view)
        for i in range(len(self.clusters)):
            ref cluster=self.clusters[i]
            var distance=(camera-cluster.center).length()
            var fade=max(Float64(0),min(Float64(1),(distance-cluster.distance)/cluster.width)) if self.transitions and cluster.width>0 else (Float64(1) if distance>=cluster.distance else Float64(0))
            if not self.enabled or not self.valid[i]:fade=0
            thresholds.append(fade)
            if fade<=0 or not frustum.visible(cluster.bounds,origin):continue
            var matrices: List[Mat4]=[Transform3D(cluster.center).matrix()]
            if fade>=1:device.draw_instances(assets.handles[cluster.proxy],matrices,cluster.material,origin,shadow)
            else:device.draw_lod_instances(assets.handles[cluster.proxy],matrices,fade,True,cluster.material,origin,shadow)
        var visible=self.cache.visible(view,origin)
        var batches=List[HLODBatch3D]()
        var lookup=Dict[String,Int]()
        for index in visible:
            var item=self.cache.items[index]
            var group=self.membership.get(item.node,-1)
            var fade=thresholds[group] if group>=0 else Float64(0)
            if fade>=1:continue
            var key=String(item.batch)+":"+String(group if fade>0 else -1)
            var found=lookup.get(key,-1)
            if found<0:
                found=len(batches);lookup[key]=found
                batches.append(HLODBatch3D(item.mesh,item.material,List[Mat4](),fade))
            batches[found].matrices.append(item.matrix)
        for batch in batches:
            if batch.threshold<=0:device.draw_instances(assets.handles[batch.mesh],batch.matrices,batch.material,origin,shadow)
            else:device.draw_lod_instances(assets.handles[batch.mesh],batch.matrices,batch.threshold,material=batch.material,origin=origin,shadow=shadow)
