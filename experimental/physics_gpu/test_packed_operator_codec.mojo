"""Actual GPU bit/read proof: all counts/masks, exceptional bits and slot reuse."""
from max.gpu.host import DeviceContext
from std.collections import Array
from std.memory import Pointer,stack_allocation,AddressSpace
from std.testing import assert_equal,assert_true
from experimental.physics_gpu.box_response_math import mask_operators,cached_normal_block
from experimental.physics_gpu.box_box import float_bits
from experimental.physics_gpu.packed_operator_codec import encode_operator_table,decode_operator_local,decode_operator_shared,structural,PACK_META
from experimental.physics_gpu.shape_kernels import POISON

def from_bits(bits: UInt64) -> Float64:
    var stored=bits;return Pointer[Float64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=stored)))[]

def proof(payload: Pointer[Float64,MutAnyOrigin],metadata: Pointer[Int32,MutAnyOrigin],output: Pointer[Int64,MutAnyOrigin]):
    var shared=stack_allocation[506,DType.float64,address_space=AddressSpace.SHARED]()
    for i in range(1,9):output[unsafe_offset=i]=0
    for epoch in range(3):
        for ordinal in range(5):
            var count=ordinal if epoch%2==0 else 4-ordinal
            for kind in range(12):
                var patch=(ordinal+kind+epoch)%3;var k=Array[Float64,16](fill=0)
                for i in range(count):
                    for j in range(count):
                        if kind==0 or kind>=8:k[i*4+j]=Float64(1+i) if i==j else Float64(0)
                        elif kind==1:k[i*4+j]=0
                        elif kind==2:k[i*4+j]=Float64((i+1)*(j+1))
                        elif kind==3:k[i*4+j]=Float64(1) if i==j and i<max(0,count-1) else Float64(0)
                        elif kind==4:k[i*4+j]=Float64(-1) if i==j else Float64(0)
                        elif kind==5:k[i*4+j]=from_bits(UInt64(9221120237041090577)) if i==j else Float64(0)
                        elif kind==6:k[i*4+j]=from_bits(UInt64(9218868437227405312)) if i==j else Float64(0)
                        else:k[i*4+j]=Float64(2+i) if i==j else Float64(.03)*Float64(i+j+1)
                var source=mask_operators(k,count)
                if kind==8:source.values[0]=from_bits(UInt64(9223372036854775808))
                if kind==9:source.values[0]=from_bits(UInt64(9221120237041090589))
                if kind==10:source.values[0]=from_bits(UInt64(9218868437227405313))
                if kind==11:
                    # Deliberately unequal mirrored active bits; no mirroring.
                    if count>=2:source.values[3*16+1]=from_bits(UInt64(4607182418800017408));source.values[3*16+4]=from_bits(UInt64(4607182418800017409))
                var before=source.values.copy();var valid=source.valid.copy()
                encode_operator_table(source.values,count,payload,metadata,patch)
                var decoded=Array[Float64,256](fill=123)
                decode_operator_local(payload,metadata,patch,count,decoded)
                for i in range(506):shared[unsafe_offset=i]=POISON
                for i in range(256):shared[unsafe_offset=113+i]=0
                decode_operator_shared(payload,metadata,patch,count,shared)
                for i in range(256):
                    if float_bits(before[i])!=float_bits(decoded[i]) or float_bits(before[i])!=float_bits(shared[unsafe_offset=113+i]) or float_bits(before[i])!=float_bits(source.values[i]):output[unsafe_offset=2]+=1
                for i in range(16):
                    if valid[i]!=source.valid[i]:output[unsafe_offset=2]+=1
                for i in range(506):
                    if (i<113 or i>368) and float_bits(shared[unsafe_offset=i])!=float_bits(POISON):output[unsafe_offset=3]+=1
                var m=1+patch*PACK_META
                if metadata[unsafe_offset=m]==0:
                    var expected=0
                    for mask in range(16):
                        if metadata[unsafe_offset=m+2+mask]!=Int32(expected):output[unsafe_offset=4]+=1
                        for row in range(4):
                            for col in range(4):
                                if structural(mask,row,col,count):expected+=1
                    if metadata[unsafe_offset=m+1]!=Int32(expected):output[unsafe_offset=4]+=1
                    output[unsafe_offset=5]+=1
                else:
                    if metadata[unsafe_offset=m+1]!=256:output[unsafe_offset=4]+=1
                    output[unsafe_offset=6]+=1
                for qkind in range(5):
                    var q=Array[Float64,4](fill=0)
                    for i in range(count):q[i]=Float64(-.1)*Float64(i+1)
                    if qkind==1:q[0]=from_bits(UInt64(9221120237041090601))
                    elif qkind==2:q[0]=from_bits(UInt64(9218868437227405312))
                    elif qkind==3:q[0]=from_bits(UInt64(9223372036854775808))
                    elif qkind==4:q[0]=1e300
                    var a=cached_normal_block(k,q,source.values,source.valid,count,1e-9);var b=cached_normal_block(k,q,decoded,source.valid,count,1e-9)
                    if a.valid!=b.valid:output[unsafe_offset=7]+=1
                    for i in range(4):
                        if float_bits(a.impulse[i])!=float_bits(b.impulse[i]):output[unsafe_offset=7]+=1
                    output[unsafe_offset=8]+=1
                output[unsafe_offset=1]+=1

def main() raises:
    with DeviceContext() as ctx:
        var payload=ctx.enqueue_create_buffer[DType.float64](16*256+2);payload.enqueue_fill(POISON)
        var metadata=ctx.enqueue_create_buffer[DType.int32](16*PACK_META+2);metadata.enqueue_fill(-98765)
        var output=ctx.enqueue_create_buffer[DType.int64](10);output.enqueue_fill(-98765)
        ctx.enqueue_function[proof](payload,metadata,output,grid_dim=1,block_dim=1);ctx.synchronize()
        with output.map_to_host() as a,payload.map_to_host() as p,metadata.map_to_host() as m:
            assert_equal(a[0],Int64(-98765));assert_equal(a[9],Int64(-98765));assert_equal(a[1],Int64(180))
            assert_equal(a[2],Int64(0));assert_equal(a[3],Int64(0));assert_equal(a[4],Int64(0));assert_equal(a[7],Int64(0));assert_equal(a[8],Int64(900));assert_true(a[5]>0 and a[6]>0)
            assert_equal(float_bits(Float64(p[0])),float_bits(POISON));assert_equal(float_bits(Float64(p[4097])),float_bits(POISON));assert_equal(m[0],Int32(-98765));assert_equal(m[289],Int32(-98765))
            print("PACKED_CODEC_BIT_READ_PASS","tables",a[1],"compact",a[5],"dense fallback",a[6],"controller reads",a[8],"all256bits/shared neighbors/flags/metadata/arena guards exact")
