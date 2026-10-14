"""Bounded little-endian Atlas binary envelopes, dependency hashes and scalars.

Header: ATLASB2 NUL, u32 version (2), u32 kind, u64 payload bytes,
u64 FNV-1a checksum. Payload begins with a bounded relative dependency table.
No unchecked foreign allocation or string scan depends on an input length.
"""
from std.ffi import external_call
from std.math import isfinite

comptime ASSET_MESH=1
comptime ASSET_SCENE=2
comptime ASSET_MANIFEST=3
comptime ASSET_SKELETON=4
comptime ASSET_CLIP=5
comptime ASSET_SKIN=6
comptime ASSET_COLLISION=7

def validate_asset_path(path: String,optional: Bool=False) raises:
    if optional and path=="-":return
    if path.byte_length()==0 or path.startswith("/") or "\\" in path or ":" in path or "\0" in path or "\t" in path or "\n" in path or "\r" in path:
        raise Error("Invalid relative asset path")
    for part in path.split("/"):
        if part==".." or part=="." or part.byte_length()==0:raise Error("Asset path escapes directory")

def read_bytes(var path: String,limit: Int=64*1024*1024) raises -> List[UInt8]:
    var fd=external_call["open",Int32,num_fixed_args=2](path.as_c_string_span(),Int32(524288))
    if fd<0:raise Error("Cannot open binary asset: "+path)
    try:
        var length=external_call["lseek",Int64](fd,Int64(0),Int32(2))
        if length<0 or length>Int64(limit):raise Error("Binary asset exceeds size limit or is not a regular seekable file")
        if external_call["lseek",Int64](fd,Int64(0),Int32(0))!=0:raise Error("Cannot seek binary asset")
        var data=List[UInt8](length=Int(length),fill=0)
        var cursor=0
        while cursor<Int(length):
            var count=external_call["pread",Int64](fd,data.unsafe_ptr().unsafe_offset(cursor),UInt64(Int(length)-cursor),Int64(cursor))
            if count<0:
                var error=external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
                if error[]==4:continue
            if count<=0:raise Error("Truncated binary asset")
            cursor+=Int(count)
        _=external_call["close",Int32](fd)
        return data^
    except error:
        _=external_call["close",Int32](fd)
        raise error^

def bytes_checksum(data: List[UInt8],start: Int=0) -> UInt64:
    var result=UInt64(14695981039346656037)
    for i in range(start,len(data)):result=(result^UInt64(data[i]))*UInt64(1099511628211)
    return result

@fieldwise_init
struct AssetDependency(Copyable,Movable):
    var path: String
    var checksum: UInt64

struct BinaryAsset:
    var bytes: List[UInt8]
    var cursor: Int
    var dependencies: List[AssetDependency]
    def __init__(out self,var path: String,kind: Int,byte_limit: Int=64*1024*1024) raises:
        self.bytes=read_bytes(path,byte_limit)
        self.cursor=0
        self.dependencies=List[AssetDependency]()
        if len(self.bytes)<36:raise Error("Truncated binary envelope")
        var magic: List[UInt8]=[65,84,76,65,83,66,50,0]
        for i in range(8):
            if self.bytes[i]!=magic[i]:raise Error("Unsupported binary asset magic")
        self.cursor=8
        if self.uint(4)!=2 or self.uint(4)!=UInt64(kind):raise Error("Unsupported binary asset version/kind")
        var size=self.uint(8)
        var checksum=self.uint(8)
        if size!=UInt64(len(self.bytes)-32) or checksum!=bytes_checksum(self.bytes,32):raise Error("Binary asset size/checksum mismatch")
        var count=self.count(4096)
        for _ in range(count):
            var dependency=self.text()
            validate_asset_path(dependency)
            for previous in self.dependencies:
                if previous.path==dependency:raise Error("Duplicate binary dependency")
            self.dependencies.append(AssetDependency(dependency^,self.uint(8)))
    def require(self,amount: Int) raises:
        if amount<0 or amount>len(self.bytes)-self.cursor:raise Error("Truncated binary asset record")
    def uint(mut self,width: Int) raises -> UInt64:
        self.require(width)
        var result=UInt64(0)
        for i in range(width):result|=UInt64(self.bytes[self.cursor+i])<<UInt64(i*8)
        self.cursor+=width
        return result
    def integer(mut self) raises -> Int:
        return Int(Int32(self.uint(4)))
    def count(mut self,maximum: Int=1000000) raises -> Int:
        var result=self.uint(4)
        if result>UInt64(maximum):raise Error("Binary asset count exceeds limit")
        return Int(result)
    def floating(mut self,width: Int=8) raises -> Float64:
        var bits=self.uint(width)
        var result: Float64
        if width==4:
            var narrow=UInt32(bits)
            result=Float64(Pointer(to=narrow).unsafe_bitcast[Float32]()[])
        else:result=Pointer(to=bits).unsafe_bitcast[Float64]()[]
        if not isfinite(result):raise Error("Non-finite binary asset value")
        return result
    def text(mut self) raises -> String:
        var length=self.count(1024*1024)
        self.require(length)
        var text=List[UInt8](length=length+1,fill=0)
        # Validate canonical UTF-8, including scalar range and overlong forms.
        var i=0
        while i<length:
            var first=Int(self.bytes[self.cursor+i])
            var width=1 if first<128 else (2 if first>=194 and first<=223 else (3 if first<=239 and first>=224 else (4 if first>=240 and first<=244 else 0)))
            if first==0 or width==0 or i+width>length:raise Error("Invalid binary asset UTF-8")
            var scalar=first&((1<<(7-width))-1) if width>1 else first
            for j in range(1,width):
                var byte=Int(self.bytes[self.cursor+i+j])
                if byte<128 or byte>191:raise Error("Invalid binary asset UTF-8 continuation")
                scalar=(scalar<<6)|(byte&63)
            if width>1 and (scalar<(128 if width==2 else (2048 if width==3 else 65536)) or scalar>1114111 or scalar>=55296 and scalar<=57343):raise Error("Invalid binary asset Unicode scalar")
            for j in range(width):text[i+j]=self.bytes[self.cursor+i+j]
            i+=width
        self.cursor+=length
        return String(unsafe_from_utf8_ptr=text.unsafe_ptr().unsafe_bitcast[Int8]())
    def finish(self) raises:
        if self.cursor!=len(self.bytes):raise Error("Unexpected binary asset trailing data")
    def identifier(mut self) raises -> String:
        var value=self.text()
        if "\t" in value or "\n" in value or "\r" in value:raise Error("Invalid binary asset identifier")
        return value^
    def validate_dependencies(self,path: String,byte_limit: Int=64*1024*1024,total_limit: Int=256*1024*1024) raises:
        var base=String(".")
        for i in range(path.byte_length()-1,-1,-1):
            if String(path[byte=i])=="/":
                base=String(path[byte=:i])
                break
        var total=0
        for dependency in self.dependencies:
            var data=read_bytes(base+"/"+dependency.path,min(byte_limit,total_limit-total))
            total+=len(data)
            if total>total_limit:raise Error("Binary asset dependency set exceeds size limit")
            if bytes_checksum(data)!=dependency.checksum:raise Error("Binary asset dependency checksum mismatch: "+dependency.path)
    def require_dependency(self,path: String,optional: Bool=False) raises:
        validate_asset_path(path,optional)
        if optional and path=="-":return
        for dependency in self.dependencies:
            if dependency.path==path:return
        raise Error("Manifest reference missing from verified dependency table: "+path)
