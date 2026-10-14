"""Cached mesh assets and culling-aware scene submission.

Stable keys address this table independent of registration order. Replacements
publish validated meshes and retain old handles through the next render.
"""
from .mesh import Mesh
from .meshio import load_mesh
from std.collections import Dict
from std.math import isfinite
from .graphics3d import Graphics3D
from .scene3d import Scene3D,Material
from .spatial import Bounds3D, Frustum
from .math3d import Vec3
from .transform3d import Mat4,Transform3D
from .assetio import BinaryAsset,ASSET_MANIFEST,validate_asset_path,read_bytes,bytes_checksum
from .durableio import read_bounded
from .triangle3d import TriangleMesh3D
from .visibility3d import SceneDrawCache,SceneDrawItem

struct AssetBatch(Copyable,Movable):
    var mesh: Int
    var material: Material
    var matrices: List[Mat4]
    def __init__(out self,mesh: Int,material: Material):
        self.mesh=mesh
        self.material=material
        self.matrices=List[Mat4]()

@fieldwise_init
struct RetiringAsset(ImplicitlyCopyable,Movable):
    var handle: Int
    var after_render: UInt64

struct Assets3D:
    var keys: List[String]
    var handles: List[Int]
    var bounds: List[Bounds3D]
    var index: Dict[String,Int]
    var checksums: Dict[String,UInt64]
    var texture_padding: Dict[Int,Float64]
    var materials: Dict[String,Material]
    var textures: Dict[String,Int]
    var texture_dependencies: Dict[Int,List[Int]]
    var retired: List[RetiringAsset]
    var retired_textures: List[RetiringAsset]
    var collision_paths: Dict[String,String]
    var revision: UInt64

    def __init__(out self):
        self.keys = List[String]()
        self.handles = List[Int]()
        self.bounds = List[Bounds3D]()
        self.index=Dict[String,Int]()
        self.checksums=Dict[String,UInt64]()
        self.texture_padding=Dict[Int,Float64]()
        self.materials=Dict[String,Material]()
        self.textures=Dict[String,Int]()
        self.texture_dependencies=Dict[Int,List[Int]]()
        self.retired=List[RetiringAsset]()
        self.retired_textures=List[RetiringAsset]()
        self.collision_paths=Dict[String,String]()
        self.revision=0

    def find(self, key: String) -> Int:
        return self.index.get(key,-1)

    def add(mut self, device: Graphics3D, var key: String, mesh: Mesh) raises -> Int:
        var found = self.find(key)
        if found >= 0: return found
        var prepared=mesh.deform_morph(mesh.morph_weights) if len(mesh.morphs)>0 else mesh.copy()
        var handle = device.upload(prepared)
        self.index[key]=len(self.keys)
        self.keys.append(key^)
        self.handles.append(handle)
        self.bounds.append(Bounds3D(prepared.minimum,prepared.maximum))
        self.revision+=1
        return len(self.keys)-1

    def load(mut self, device: Graphics3D, path: String) raises -> Int:
        var found = self.find(path)
        if found >= 0: return found
        var mesh = load_mesh(path)
        return self.add(device,path,mesh)

    def replace_mesh(mut self,device: Graphics3D,key: String,mesh: Mesh) raises:
        """Prepare before publication; queued draws retain their previous handle.

        collect() after a successful render (also called by draw()) releases
        retired handles; native submission serials protect their GPU slices.
        """
        var found=self.find(key)
        if found<0:raise Error("Cannot replace unknown mesh asset: "+key)
        var prepared=mesh.deform_morph(mesh.morph_weights) if len(mesh.morphs)>0 else mesh.copy()
        var handle=device.upload(prepared)
        self.retired.append(RetiringAsset(self.handles[found],device.frame_stat(1)+1))
        self.checksums[key]=0
        self.handles[found]=handle
        self.bounds[found]=Bounds3D(prepared.minimum,prepared.maximum)
        self.revision+=1

    def reload_mesh(mut self,device: Graphics3D,key: String,path: String) raises:
        var mesh=load_mesh(path)
        self.replace_mesh(device,key,mesh)

    def collect(mut self,device: Graphics3D) raises:
        var kept=List[RetiringAsset]()
        for asset in self.retired:
            if asset.after_render<=device.frame_stat(1):device.release(asset.handle)
            else:kept.append(asset)
        self.retired=kept^
        # Albedo release removes attachments, then its map textures can retire.
        var changed=True
        while changed:
            changed=False
            var pending=List[RetiringAsset]()
            for asset in self.retired_textures:
                if asset.after_render<=device.frame_stat(1) and device.texture_releasable(asset.handle):
                    device.release_texture(asset.handle)
                    if asset.handle in self.texture_padding:_=self.texture_padding.pop(asset.handle)
                    changed=True
                else:pending.append(asset)
            self.retired_textures=pending^

    def node_mesh(self, scene: Scene3D, node: Int) raises -> Int:
        var key=scene.nodes[node].asset_key.copy()
        var index=self.find(key) if key.byte_length()>0 else scene.nodes[node].mesh
        if (key.byte_length()>0 and index<0) or index < -1 or index>=len(self.handles):raise Error("Scene references unknown mesh asset: "+key)
        return index

    def node_material(self, scene: Scene3D, node: Int) raises -> Material:
        var key=scene.nodes[node].material_key.copy()
        if key.byte_length()==0:return scene.nodes[node].material
        if key not in self.materials:raise Error("Scene references unknown material: "+key)
        return self.materials[key]

    def load_manifest(mut self, device: Graphics3D, path: String) raises:
        """Rows: mesh ID path; material ID texture RGB roughness metallic emission.

        Paths are relative to the manifest directory. IDs survive file reordering.
        """
        var base=String(".")
        for i in range(path.byte_length()-1,-1,-1):
            if String(path[byte=i])=="/":
                base=String(path[byte=:i])
                break
        var source: String
        if path.endswith(".atlasb"):
            var binary=BinaryAsset(path,ASSET_MANIFEST)
            binary.validate_dependencies(path)
            source="ATLAS_ASSETS_1\n"
            var count=binary.count(100000)
            for _ in range(count):
                var kind=binary.uint(4)
                var key=binary.identifier()
                var filename=binary.identifier()
                binary.require_dependency(filename,kind==2 or kind==4 or kind==5)
                if kind==1:source+="mesh\t"+key+"\t"+filename+"\n"
                elif kind==3:source+="collision\t"+key+"\t"+filename+"\n"
                elif kind==2 or kind==4 or kind==5:
                    source+="material\t"+key+"\t"+filename
                    for _ in range(6):source+="\t"+String(binary.floating())
                    var normal=binary.identifier()
                    var orm=binary.identifier()
                    binary.require_dependency(normal,True)
                    binary.require_dependency(orm,True)
                    source+="\t"+normal+"\t"+orm
                    if kind==4 or kind==5:
                        for _ in range(13):source+="\t"+String(binary.uint(4))
                        source+="\t"+String(binary.floating())
                    if kind==5:
                        source+="\t"+String(binary.floating())+"\t"+String(binary.uint(4))+"\t"+String(binary.floating())
                    source+="\n"
                else:raise Error("Invalid binary manifest row kind")
            binary.finish()
        else:source=read_bounded(path)
        var lines=source.split("\n")
        if len(lines)==0 or String(lines[0])!="ATLAS_ASSETS_1":raise Error("Unsupported asset manifest")
        var seen=Dict[String,Bool]()
        # Validate every reference before publishing any row.
        for i in range(1,len(lines)):
            var fields=String(lines[i]).split("\t")
            if fields[0].byte_length()==0:continue
            var kind=String(fields[0])
            if (kind=="mesh" or kind=="collision") and len(fields)==3:validate_asset_path(String(fields[2]))
            elif kind=="material" and (len(fields)==9 or len(fields)==11 or len(fields)==25 or len(fields)==28):
                validate_asset_path(String(fields[2]),True)
                if len(fields)>=11:
                    validate_asset_path(String(fields[9]),True)
                    validate_asset_path(String(fields[10]),True)
                for column in range(3,9):
                    var value=Float64(String(fields[column]))
                    if not isfinite(value):raise Error("Non-finite material value")
                if len(fields)>=25:
                    for offset in range(11,23,4):
                        var s=Int(String(fields[offset]))
                        var t=Int(String(fields[offset+1]))
                        var min_filter=Int(String(fields[offset+2]))
                        var mag_filter=Int(String(fields[offset+3]))
                        if (s!=10497 and s!=33071 and s!=33648) or (t!=10497 and t!=33071 and t!=33648) or (min_filter!=9728 and min_filter!=9729 and min_filter!=9984 and min_filter!=9985 and min_filter!=9986 and min_filter!=9987) or (mag_filter!=9728 and mag_filter!=9729):raise Error("Invalid material sampler policy")
                    var mode=Int(String(fields[23]))
                    var cutoff=Float64(String(fields[24]))
                    if mode<0 or mode>2 or not isfinite(cutoff) or cutoff<0 or cutoff>1:raise Error("Invalid material alpha policy")
                if len(fields)==28:
                    var transmission=Float64(String(fields[25]));var wind=Int(String(fields[26]));var padding=Float64(String(fields[27]))
                    if String(fields[2])=="-" or not isfinite(transmission) or transmission<0 or transmission>1 or (wind!=0 and wind!=1) or not isfinite(padding) or padding<0 or padding>16 or wind!=0 and (transmission<=0 or padding<.201):raise Error("Invalid foliage policy")
            else:raise Error("Invalid asset manifest row")
            var identity=kind+":"+String(fields[1])
            if fields[1].byte_length()==0 or identity in seen:raise Error("Empty or duplicate manifest identity")
            seen[identity]=True
        for i in range(1,len(lines)):
            var fields=String(lines[i]).split("\t")
            if fields[0].byte_length()==0:continue
            if String(fields[0])=="mesh" and len(fields)==3:
                var key=String(fields[1])
                var filename=base+"/"+String(fields[2])
                var mesh=load_mesh(filename)
                var hash=bytes_checksum(read_bytes(filename))
                var existing=self.find(key)
                _=self.add(device,key,mesh)
                if existing<0:self.checksums[key]=hash
            elif String(fields[0])=="collision" and len(fields)==3:
                self.collision_paths[String(fields[1])]=base+"/"+String(fields[2])
            elif String(fields[0])=="material" and (len(fields)==9 or len(fields)==11 or len(fields)==25 or len(fields)==28):
                var texture=-1
                if String(fields[2])!="-":
                    var filename=base+"/"+String(fields[2])
                    var cache_key=filename
                    if len(fields)>=11:cache_key+=":"+String(fields[9])+":"+String(fields[10])
                    if len(fields)>=25:
                        for column in range(11,len(fields)):cache_key+=":"+String(fields[column])
                    if cache_key not in self.textures:self.textures[cache_key]=device.texture(filename)
                    texture=self.textures[cache_key]
                    if len(fields)>=25:
                        device.texture_sampling(texture,Int(String(fields[11])),Int(String(fields[12])),Int(String(fields[13])),Int(String(fields[14])))
                        device.texture_alpha(texture,Int(String(fields[23])),Float64(String(fields[24])))
                if len(fields)>=11:
                    var dependencies=List[Int]()
                    for column in range(9,11):
                        if String(fields[column])=="-":continue
                        if texture<0:raise Error("Mapped material requires albedo texture")
                        var filename=base+"/"+String(fields[column])
                        var map_key=filename.copy()
                        var offset=15 if column==9 else 19
                        if len(fields)>=25:
                            for setting in range(offset,offset+4):map_key+=":"+String(fields[setting])
                        if map_key not in self.textures:self.textures[map_key]=device.normal_texture(filename)
                        var map_texture=self.textures[map_key]
                        if len(fields)>=25:device.texture_sampling(map_texture,Int(String(fields[offset])),Int(String(fields[offset+1])),Int(String(fields[offset+2])),Int(String(fields[offset+3])))
                        if column==9:device.normal_map(texture,map_texture)
                        else:device.orm_map(texture,map_texture)
                        dependencies.append(map_texture)
                    if texture>=0:self.texture_dependencies[texture]=dependencies^
                if len(fields)==28:
                    device.foliage(texture,Float64(String(fields[25])))
                    device.wind_material(texture,Int(String(fields[26]))!=0)
                    self.texture_padding[texture]=Float64(String(fields[27]))
                self.materials[String(fields[1])]=Material(Vec3(Float64(String(fields[3])),Float64(String(fields[4])),Float64(String(fields[5]))),Float64(String(fields[6])),Float64(String(fields[7])),Float64(String(fields[8])),texture)
            else:raise Error("Invalid asset manifest row")
        self.revision+=1

    def validate(self, scene: Scene3D) raises:
        for i in range(len(scene.nodes)):
            if scene.valid(i):
                _=self.node_mesh(scene,i)
                _=self.node_material(scene,i)

    def reload_manifest(mut self,device: Graphics3D,path: String,scene: Scene3D) raises:
        """Prepare a bundle privately, check references, then publish replacements.

        Existing unrelated registrations remain available. Old textures retire
        after queued consumers and submissions complete; handles are generational.
        """
        var candidate=Self()
        try:
            candidate.load_manifest(device,path)
            for i in range(len(scene.nodes)):
                if not scene.valid(i):continue
                var key=scene.nodes[i].asset_key.copy()
                if key.byte_length()>0 and candidate.find(key)<0 and self.find(key)<0:raise Error("Reload contains missing scene mesh: "+key)
                key=scene.nodes[i].material_key.copy()
                if key.byte_length()>0 and key not in candidate.materials and key not in self.materials:raise Error("Reload contains missing scene material: "+key)
        except error:
            candidate.close(device)
            raise error^
        # No I/O or GPU allocation occurs after this publication boundary.
        var owned=Dict[Int,Bool]()
        for key in self.textures:owned[self.textures[key]]=True
        for i in range(len(candidate.keys)):
            var key=candidate.keys[i].copy()
            var found=self.find(key)
            if found<0:
                self.index[key]=len(self.keys)
                self.keys.append(key^)
                self.handles.append(candidate.handles[i])
                self.bounds.append(candidate.bounds[i])
            else:
                self.retired.append(RetiringAsset(self.handles[found],device.frame_stat(1)+1))
                self.handles[found]=candidate.handles[i]
                self.bounds[found]=candidate.bounds[i]
        for texture in candidate.texture_padding:self.texture_padding[texture]=candidate.texture_padding[texture]
        for key in candidate.checksums:self.checksums[key]=candidate.checksums[key]
        for key in candidate.materials:self.materials[key]=candidate.materials[key]
        for key in candidate.textures:self.textures[key]=candidate.textures[key]
        for key in candidate.texture_dependencies:self.texture_dependencies[key]=candidate.texture_dependencies[key].copy()
        for key in candidate.collision_paths:self.collision_paths[key]=candidate.collision_paths[key]
        var needed=Dict[Int,Bool]()
        for key in self.materials:
            var texture=self.materials[key].texture
            if texture<0:continue
            needed[texture]=True
            if texture in self.texture_dependencies:
                for dependency in self.texture_dependencies[texture]:needed[dependency]=True
        var active=Dict[String,Int]()
        var retiring=Dict[Int,Bool]()
        for key in self.textures:
            var texture=self.textures[key]
            if texture in needed:active[key]=texture
            owned[texture]=True
        for texture in owned:
            if texture not in needed and texture not in retiring:
                self.retired_textures.append(RetiringAsset(texture,device.frame_stat(1)+1))
                retiring[texture]=True
        self.textures=active^
        var dependencies=Dict[Int,List[Int]]()
        for texture in needed:
            if texture in self.texture_dependencies:dependencies[texture]=self.texture_dependencies[texture].copy()
        self.texture_dependencies=dependencies^
        self.revision+=1

    def collider(self,key: String,matrix: Mat4=Mat4(),payload_budget: Int=128*1024*1024) raises -> TriangleMesh3D:
        if key not in self.collision_paths:raise Error("No authored collision for asset: "+key)
        return TriangleMesh3D.load(self.collision_paths[key],matrix,payload_budget)

    def geometry_batch(self,mesh: Int) -> String:
        var checksum=self.checksums.get(self.keys[mesh],0)
        return "c"+String(checksum) if checksum!=0 else "m"+String(mesh)

    def prepare_scene(self,scene: Scene3D,mut cache: SceneDrawCache,revision: Int) raises:
        if cache.matches(revision,self.revision,len(scene.nodes)):return
        if len(scene.nodes)>100000:raise Error("Scene exceeds visibility node budget")
        self.validate(scene)
        var matrices=scene.world_matrices()
        var candidate=SceneDrawCache()
        var groups=Dict[String,Int]()
        for i in range(len(scene.nodes)):
            if not scene.valid(i):continue
            var mesh=self.node_mesh(scene,i)
            if mesh<0:continue
            var material=self.node_material(scene,i)
            var key=self.geometry_batch(mesh)+":"+String(material.texture)+":"+String(material.color.x)+":"+String(material.color.y)+":"+String(material.color.z)+":"+String(material.roughness)+":"+String(material.metallic)+":"+String(material.emission)
            if key not in groups:groups[key]=len(groups)
            candidate.items.append(SceneDrawItem(i,mesh,matrices[i],material,self.bounds[mesh].padded(self.texture_padding.get(material.texture,0)).transformed(matrices[i]),groups[key]))
        candidate.build()
        candidate.scene_revision=revision
        candidate.asset_revision=self.revision
        candidate.node_count=len(scene.nodes)
        candidate.ready=True
        candidate.builds=cache.builds+1
        cache=candidate^

    def draw_cached(mut self,device: Graphics3D,scene: Scene3D,mut cache: SceneDrawCache,revision: Int,origin: Vec3,view_projection: Mat4,shadow: Bool=False,hierarchical: Bool=True,hidden: Dict[String,Bool]=Dict[String,Bool]()) raises:
        """Change revision or invalidate the scene-owned cache after any edit.

        Mesh/material reloads rebuild automatically. Ordinary draw() remains an
        uncached path for callers that mutate nodes without a revision contract.
        """
        self.collect(device)
        self.prepare_scene(scene,cache,revision)
        var visible=cache.visible(view_projection,origin,hierarchical)
        var batches=List[AssetBatch]()
        var lookup=Dict[Int,Int]()
        for index in visible:
            var item=cache.items[index]
            if hidden.get(self.keys[item.mesh],False):continue
            var material=item.material
            var found=lookup.get(item.batch,-1)
            if found<0:
                found=len(batches)
                lookup[item.batch]=found
                batches.append(AssetBatch(item.mesh,material))
            batches[found].matrices.append(item.matrix)
        for batch in batches:device.draw_instances(self.handles[batch.mesh],batch.matrices,batch.material,origin,shadow)

    def draw(mut self, device: Graphics3D, scene: Scene3D, origin: Vec3, view_projection: Mat4, shadow: Bool = False, batched: Bool=True,overrides: Dict[Int,Transform3D]=Dict[Int,Transform3D](),hidden: Dict[String,Bool]=Dict[String,Bool]()) raises:
        self.collect(device)
        self.validate(scene)
        var frustum=Frustum(view_projection)
        var matrices=scene.world_matrices(overrides)
        var batches=List[AssetBatch]()
        var lookup=Dict[String,Int]()
        for i in range(len(scene.nodes)):
            if not scene.valid(i):continue
            var mesh=self.node_mesh(scene,i)
            if mesh<0 or hidden.get(self.keys[mesh],False):continue
            var matrix=matrices[i]
            var material=self.node_material(scene,i)
            if not frustum.visible(self.bounds[mesh].padded(self.texture_padding.get(material.texture,0)).transformed(matrix),origin):continue
            if not batched:
                if shadow:device.shadow_material(self.handles[mesh],matrix,material.texture,origin)
                else:device.draw(self.handles[mesh],matrix,material,origin)
                continue
            var key=self.geometry_batch(mesh)+":"+String(material.texture)+":"+String(material.color.x)+":"+String(material.color.y)+":"+String(material.color.z)+":"+String(material.roughness)+":"+String(material.metallic)+":"+String(material.emission)
            var found=lookup.get(key,-1)
            if found<0:
                found=len(batches)
                lookup[key]=found
                batches.append(AssetBatch(mesh,material))
            batches[found].matrices.append(matrix)
        for batch in batches:device.draw_instances(self.handles[batch.mesh],batch.matrices,batch.material,origin,shadow)

    def pick(self, scene: Scene3D, origin: Vec3, direction: Vec3, maximum: Float64 = 10000) raises -> Int:
        self.validate(scene)
        var nearest = maximum
        var selected = -1
        for i in range(len(scene.nodes)):
            if not scene.valid(i): continue
            var mesh = self.node_mesh(scene,i)
            if mesh < 0: continue
            var distance = self.bounds[mesh].transformed(scene.world_matrix(i)).ray(origin,direction.unit(),nearest)
            if distance >= 0 and distance <= nearest:
                selected = i
                nearest = distance
        return selected

    def close(mut self, device: Graphics3D) raises:
        for handle in self.handles: device.release(handle)
        for asset in self.retired:device.release(asset.handle)
        self.retired.clear()
        var retiring=Dict[Int,Bool]()
        for asset in self.retired_textures:retiring[asset.handle]=True
        for key in self.textures:
            var texture=self.textures[key]
            if texture not in retiring:
                self.retired_textures.append(RetiringAsset(texture,0))
                retiring[texture]=True
        device.wait_idle()
        for i in range(len(self.retired_textures)):self.retired_textures[i].after_render=0
        self.collect(device)
        self.keys.clear()
        self.handles.clear()
        self.bounds.clear()
        self.index.clear()
        self.checksums.clear()
        self.texture_padding.clear()
        self.materials.clear()
        self.textures.clear()
        self.texture_dependencies.clear()
        self.collision_paths.clear()
