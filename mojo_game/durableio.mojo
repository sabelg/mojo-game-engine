"""Bounded reads and Linux durable atomic writes for versioned project data."""
from std.ffi import external_call

def exists(var path: String) raises -> Bool:
    if external_call["access",Int32](path.as_c_string_span(),Int32(0))==0:return True
    var error=external_call["__errno_location",Pointer[Int32,MutUntrackedOrigin]]()
    if error[]!=2:raise Error("Cannot access project data: "+path)
    return False

def read_bounded(path: String,limit: Int=64*1024*1024) raises -> String:
    with open(path,"r") as file:
        var data=file.read(limit+1)
        if data.byte_length()>limit:raise Error("Project data exceeds size limit")
        return data^

def sync_path(var path: String) raises:
    var fd=external_call["open",Int32,num_fixed_args=2](path.as_c_string_span(),Int32(524288))
    if fd<0:raise Error("Cannot open project data for synchronization")
    var result=external_call["fsync",Int32](fd)
    _=external_call["close",Int32](fd)
    if result!=0:raise Error("Cannot synchronize project data")

def atomic_write(var path: String,data: String) raises:
    if data.byte_length()>64*1024*1024:raise Error("Project data exceeds size limit")
    var temporary=path+".tmp-"+object_id()
    try:
        with open(temporary,"w") as file:file.write(data)
        sync_path(temporary)
        if external_call["rename",Int32](temporary.as_c_string_span(),path.as_c_string_span())!=0:raise Error("Cannot replace project data")
        var parent=String(".")
        for i in range(path.byte_length()-1,-1,-1):
            if String(path[byte=i])=="/":
                parent=String(path[byte=:i]) if i>0 else String("/")
                break
        sync_path(parent)
    except error:
        _=external_call["unlink",Int32](temporary.as_c_string_span())
        raise error^

def checksum(var data: String) -> UInt64:
    var result=UInt64(14695981039346656037)
    var pointer=data.as_c_string_span().ptr().unsafe_bitcast[UInt8]()
    for i in range(data.byte_length()):result=(result^UInt64(pointer[unsafe_offset=i]))*UInt64(1099511628211)
    return result

def object_id() raises -> String:
    from std.collections import Array
    var bytes=Array[UInt8,16](fill=0)
    if external_call["getrandom",Int64](Pointer(to=bytes).unsafe_bitcast[UInt8](),UInt64(16),UInt32(0))!=16:raise Error("Cannot create persistent object identity")
    var result=String()
    for byte in bytes:result+=String(Int(byte))+"-"
    _=bytes
    return result^
