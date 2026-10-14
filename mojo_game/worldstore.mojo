"""Single-writer, recoverable multi-cell transactions with a durable redo journal.

The manifest rename is the commit point. Recovery validates every payload before
replaying any cell and never derives paths from untrusted manifest text.
"""
from std.ffi import external_call
from .scene3d import Scene3D
from .terrainlayer import TerrainLayer,TERRAIN_CELL
from .durableio import exists,read_bounded,sync_path,atomic_write,checksum
from std.collections import Dict

struct CellSnapshot(Copyable,Movable):
    var x: Int
    var z: Int
    var revision: Int
    var scene: Scene3D
    def __init__(out self,x: Int,z: Int,revision: Int,var scene: Scene3D):
        self.x=x
        self.z=z
        self.revision=revision
        self.scene=scene^

def cell_name(x: Int,z: Int) -> String:return "cell_"+String(x)+"_"+String(z)+".scene"

def recover_world(directory: String) raises -> Bool:
    var journal=directory+"/.atlas-transaction"
    var manifest=journal+"/commit"
    if not exists(manifest):return False
    var lines=read_bounded(manifest,256*1024).split("\n")
    if len(lines)<2 or String(lines[0])!="ATLAS_TRANSACTION_1":raise Error("Invalid world transaction")
    var names=List[String]()
    var payloads=List[String]()
    var seen=Dict[String,Bool]()
    var total_bytes=0
    for i in range(1,len(lines)):
        if lines[i].byte_length()==0:continue
        if len(names)>=4096:raise Error("World transaction exceeds cell limit")
        var fields=String(lines[i]).split("\t")
        if len(fields)!=3:raise Error("Invalid world transaction record")
        var name=cell_name(Int(String(fields[0])),Int(String(fields[1])))
        if name in seen:raise Error("Duplicate world transaction cell")
        seen[name]=True
        var payload=read_bounded(journal+"/"+name)
        if String(checksum(payload))!=String(fields[2]):raise Error("World transaction checksum mismatch")
        total_bytes+=payload.byte_length()
        if total_bytes>256*1024*1024:raise Error("World transaction exceeds byte budget")
        var verified=Scene3D.decode(payload)
        if name==cell_name(TERRAIN_CELL,TERRAIN_CELL):_=TerrainLayer.from_scene(verified)
        names.append(name^)
        payloads.append(payload^)
    if len(names)==0:raise Error("Empty world transaction")
    for i in range(len(names)):atomic_write(directory+"/"+names[i],payloads[i])
    sync_path(directory)
    if external_call["unlink",Int32](manifest.as_c_string_span())!=0:raise Error("Cannot retire world transaction")
    sync_path(journal)
    for name in names:
        var path=journal+"/"+name
        _=external_call["unlink",Int32](path.as_c_string_span())
    return True

def commit_world(directory: String,snapshots: List[CellSnapshot],fault: Int=0) raises:
    if len(snapshots)==0:return
    if len(snapshots)>4096:raise Error("World transaction exceeds cell limit")
    _=recover_world(directory)
    var journal=directory+"/.atlas-transaction"
    if not exists(journal):
        if external_call["mkdir",Int32](journal.as_c_string_span(),Int(448))!=0:raise Error("Cannot create world journal")
        sync_path(directory)
    var manifest=String("ATLAS_TRANSACTION_1\n")
    var seen=Dict[String,Bool]()
    var total_bytes=0
    for snapshot in snapshots:
        var name=cell_name(snapshot.x,snapshot.z)
        if name in seen:raise Error("Duplicate snapshot cell")
        seen[name]=True
        var payload=snapshot.scene.encode()
        total_bytes+=payload.byte_length()
        if total_bytes>256*1024*1024:raise Error("World transaction exceeds byte budget")
        var verified=Scene3D.decode(payload)
        if name==cell_name(TERRAIN_CELL,TERRAIN_CELL):_=TerrainLayer.from_scene(verified)
        atomic_write(journal+"/"+name,payload)
        manifest+=String(snapshot.x)+"\t"+String(snapshot.z)+"\t"+String(checksum(payload))+"\n"
    sync_path(journal)
    if fault==1:raise Error("Injected interruption before commit")
    atomic_write(journal+"/commit",manifest)
    sync_path(journal)
    if fault==2:raise Error("Injected interruption after commit")
    if fault==3:
        atomic_write(directory+"/"+cell_name(snapshots[0].x,snapshots[0].z),snapshots[0].scene.encode())
        sync_path(directory)
        raise Error("Injected interruption during replay")
    _=recover_world(directory)

struct WorldStore:
    var directory: String
    var lock_fd: Int32
    var recoveries: Int
    var commits: Int
    def __init__(out self,var directory: String):
        self.directory=directory^
        self.lock_fd=-1
        self.recoveries=0
        self.commits=0
    def prepare(mut self) raises:
        if self.lock_fd>=0:return
        var path=self.directory+"/.atlas-world.lock"
        var fd=external_call["open",Int32,num_fixed_args=2](path.as_c_string_span(),Int32(524354),Int32(384))
        if fd<0:raise Error("Cannot open world lock; create the project directory first")
        if external_call["flock",Int32](fd,Int32(6))!=0:
            _=external_call["close",Int32](fd)
            raise Error("World is already open by another writer")
        self.lock_fd=fd
        try:
            if recover_world(self.directory):self.recoveries+=1
        except error:
            self.close()
            raise Error(String(error))
    def commit(mut self,snapshots: List[CellSnapshot],fault: Int=0) raises:
        self.prepare()
        commit_world(self.directory,snapshots,fault)
        if len(snapshots)>0:self.commits+=1
    def close(mut self):
        if self.lock_fd>=0:
            _=external_call["close",Int32](self.lock_fd)
            self.lock_fd=-1
    def __deinit__(deinit self):self.close()
