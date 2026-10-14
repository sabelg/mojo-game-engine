"""Private-pose projection validation and guarded snapshot, no body publication."""
from std.memory import Pointer
from std.math import isfinite
from max.gpu import block_idx,block_dim,thread_idx
from .kernels import WORDS,load
from .response_kernels import SLOP,POS_TOL

def validate_projected(headers: Pointer[UInt64,MutAnyOrigin],count: Int32,projected: Pointer[Float64,MutAnyOrigin],new_headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],post_summary: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    if post_summary[unsafe_offset=0]!=0:summary[unsafe_offset=0]=65;return
    for i in range(Int(post_summary[unsafe_offset=2])):
        var matched=False
        for old in range(Int(count)):
            var equal=True
            for f in range(11):
                if new_headers[unsafe_offset=1+i*11+f]!=headers[unsafe_offset=1+old*11+f]:equal=False
            if equal:matched=True;break
        if not matched:summary[unsafe_offset=0]=65;return
        var a=load(projected,Int(new_headers[unsafe_offset=1+i*11+3]));var b=load(projected,Int(new_headers[unsafe_offset=1+i*11+8]))
        if a.mass==0 and b.mass==0:continue
        var separation=geometry[unsafe_offset=1+i*10+3]
        if not isfinite(separation) or separation < -SLOP-POS_TOL:summary[unsafe_offset=0]=60;return

def copy_projected(source: Pointer[Float64,MutAnyOrigin],destination: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i<WORDS and summary[unsafe_offset=0]==0:destination[unsafe_offset=i]=source[unsafe_offset=i]
