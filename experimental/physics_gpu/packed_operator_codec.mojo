"""Bit-preserving active-mask transport; arithmetic reads retain dense layout."""
from std.collections import Array
from std.memory import Pointer,AddressSpace
from .box_box import float_bits

comptime PACK_WORDS=256
comptime PACK_META=18
comptime SharedFloat=Pointer[Float64,MutUntrackedOrigin,address_space=AddressSpace.SHARED]

def structural(mask: Int,row: Int,col: Int,count: Int) -> Bool:
    return mask<(1<<count) and row<count and col<count and (mask&(1<<row))!=0 and (mask&(1<<col))!=0

def encode_operator_table(values: Array[Float64,256],count: Int,payload: Pointer[Float64,MutAnyOrigin],metadata: Pointer[Int32,MutAnyOrigin],patch: Int):
    var m=1+patch*PACK_META;var base=1+patch*PACK_WORDS;var dense=False
    # A lossless fallback, not a floating comparison: -0 and every nonzero/NaN
    # payload outside the live structural set must survive reconstruction.
    for mask in range(16):
        for row in range(4):
            for col in range(4):
                if not structural(mask,row,col,count) and float_bits(values[mask*16+row*4+col])!=UInt64(0):dense=True
    metadata[unsafe_offset=m]=Int32(1 if dense else 0)
    if dense:
        metadata[unsafe_offset=m+1]=256
        for mask in range(16):metadata[unsafe_offset=m+2+mask]=Int32(mask*16)
        for i in range(256):payload[unsafe_offset=base+i]=values[i]
    else:
        var used=0
        for mask in range(16):
            metadata[unsafe_offset=m+2+mask]=Int32(used)
            for row in range(4):
                for col in range(4):
                    if structural(mask,row,col,count):payload[unsafe_offset=base+used]=values[mask*16+row*4+col];used+=1
        metadata[unsafe_offset=m+1]=Int32(used)

def decode_operator_local(payload: Pointer[Float64,MutAnyOrigin],metadata: Pointer[Int32,MutAnyOrigin],patch: Int,count: Int,mut result: Array[Float64,256]):
    var m=1+patch*PACK_META;var base=1+patch*PACK_WORDS
    for i in range(256):result[i]=0
    if metadata[unsafe_offset=m]!=0:
        for i in range(256):result[i]=payload[unsafe_offset=base+i]
    else:
        for mask in range(16):
            var cursor=Int(metadata[unsafe_offset=m+2+mask])
            for row in range(4):
                for col in range(4):
                    if structural(mask,row,col,count):result[mask*16+row*4+col]=payload[unsafe_offset=base+cursor];cursor+=1

def decode_operator_shared(payload: Pointer[Float64,MutAnyOrigin],metadata: Pointer[Int32,MutAnyOrigin],patch: Int,count: Int,result: SharedFloat):
    var m=1+patch*PACK_META;var base=1+patch*PACK_WORDS
    # The caller retains the original256-word positive-zero initialization.
    if metadata[unsafe_offset=m]!=0:
        for i in range(256):result[unsafe_offset=113+i]=payload[unsafe_offset=base+i]
    else:
        for mask in range(16):
            var cursor=Int(metadata[unsafe_offset=m+2+mask])
            for row in range(4):
                for col in range(4):
                    if structural(mask,row,col,count):result[unsafe_offset=113+mask*16+row*4+col]=payload[unsafe_offset=base+cursor];cursor+=1
