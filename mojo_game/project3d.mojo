"""Durable project settings and shell-free asynchronous project operations."""
from std.collections import Dict
from std.math import isfinite
from std.ffi import external_call
from .durableio import read_bounded,atomic_write
from .assetio import validate_asset_path
from .sdl import NullableHandle

struct Project3D(Copyable,Movable):
    var name: String
    var cell_size: Float64
    var seed: Int
    var manifests: List[String]
    def __init__(out self,var name: String="Atlas world"):
        self.name=name^
        self.cell_size=256
        self.seed=42
        self.manifests=List[String]()
    def encode(self) raises -> String:
        if self.name.byte_length()==0 or self.name.byte_length()>128 or "\0" in self.name or "\t" in self.name or "\n" in self.name or "\r" in self.name or not isfinite(self.cell_size) or self.cell_size<1 or self.cell_size>4096 or self.seed < -2147483648 or self.seed>2147483647 or len(self.manifests)>256:raise Error("Invalid project settings")
        var seen=Dict[String,Bool]()
        var data="ATLAS_PROJECT_1\nname\t"+self.name+"\ncell_size\t"+String(self.cell_size)+"\nseed\t"+String(self.seed)+"\n"
        for manifest in self.manifests:
            validate_asset_path(manifest)
            if manifest in seen:raise Error("Duplicate project manifest")
            seen[manifest]=True
            data+="manifest\t"+manifest+"\n"
        return data^
    def save(self,directory: String) raises:atomic_write(directory+"/atlas.project",self.encode())
    @staticmethod
    def load(directory: String) raises -> Self:
        var lines=read_bounded(directory+"/atlas.project",256*1024).split("\n")
        if len(lines)<4 or String(lines[0])!="ATLAS_PROJECT_1":raise Error("Unsupported project settings")
        var result=Self()
        var seen=Dict[String,Bool]()
        for i in range(1,len(lines)):
            if lines[i].byte_length()==0:continue
            var fields=String(lines[i]).split("\t")
            if len(fields)!=2:raise Error("Invalid project setting")
            var key=String(fields[0])
            var value=String(fields[1])
            if key=="manifest":
                if len(result.manifests)>=256:raise Error("Too many project manifests")
                result.manifests.append(value^)
                continue
            if key in seen:raise Error("Duplicate project setting")
            seen[key]=True
            if key=="name":result.name=value^
            elif key=="cell_size":result.cell_size=Float64(value)
            elif key=="seed":result.seed=Int(value)
            else:raise Error("Unknown project setting")
        if len(seen)!=3:raise Error("Incomplete project settings")
        _=result.encode()
        return result^

struct ProjectOperation:
    var pid: Int32
    var exit_code: Int
    def __init__(out self):
        self.pid=0
        self.exit_code=0
    def start(mut self,var arguments: List[String]) raises:
        if self.pid!=0:raise Error("A project operation is already running")
        if len(arguments)<2 or len(arguments)>32:raise Error("Invalid project command")
        var argv=List[UInt64]()
        for i in range(len(arguments)):
            if "\0" in arguments[i] or arguments[i].byte_length()>4096:raise Error("Invalid project command argument")
            argv.append(UInt64(Int(arguments[i].as_c_string_span().ptr())))
        argv.append(0)
        var environment=List[String]()
        for key in [String("PATH"),String("LD_LIBRARY_PATH"),String("DISPLAY"),String("WAYLAND_DISPLAY"),String("XAUTHORITY"),String("XDG_RUNTIME_DIR"),String("SDL_VIDEO_DRIVER"),String("SDL_AUDIO_DRIVER"),String("MOJO_VK_SOFTWARE"),String("MOJO_VK_REQUIRE_HARDWARE"),String("MOJO_VK_VALIDATION"),String("VK_LAYER_VALIDATE_SYNC"),String("VK_LAYER_PATH"),String("VK_DRIVER_FILES"),String("ATLAS_USD_STAGE"),String("ATLAS_USD_INSPECT"),String("ATLAS_BLENDER")]:
            var lookup=key.copy()
            var value=external_call["getenv",NullableHandle](lookup.as_c_string_span())
            if value:environment.append(key+"="+String(unsafe_from_utf8_ptr=value.value().unsafe_bitcast[Int8]()))
        environment.append("PYTHONNOUSERSITE=1")
        var envp=List[UInt64]()
        for i in range(len(environment)):envp.append(UInt64(Int(environment[i].as_c_string_span().ptr())))
        envp.append(0)
        var pid=Int32(0)
        var result=external_call["posix_spawnp",Int32](Pointer(to=pid),arguments[0].as_c_string_span(),UInt64(0),UInt64(0),argv.unsafe_ptr(),envp.unsafe_ptr())
        # Keep owned strings alive across the foreign spawn call.
        for argument in arguments:_=argument.byte_length()
        for entry in environment:_=entry.byte_length()
        if result!=0:raise Error("Cannot launch project operation: "+String(result))
        self.pid=pid
        self.exit_code=-1
    def poll(mut self) raises -> Bool:
        if self.pid==0:return True
        var status=Int32(0)
        var result=external_call["waitpid",Int32](self.pid,Pointer(to=status),Int32(1))
        if result==0:return False
        if result<0:
            var errno=external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
            if errno[]==4:return False
            raise Error("Cannot collect project operation")
        self.pid=0
        self.exit_code=Int((status>>8)&255) if (status&127)==0 else 128+Int(status&127)
        return True
    def close(mut self):
        if self.pid>0:
            _=external_call["kill",Int32](self.pid,Int32(15))
            var status=Int32(0)
            while external_call["waitpid",Int32](self.pid,Pointer(to=status),Int32(0))<0:
                var errno=external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
                if errno[]!=4:break
            self.pid=0
    def __deinit__(deinit self):self.close()
