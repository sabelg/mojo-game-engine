"""Bounded exact retry snapshots and current-pressure seed disk proof."""
from std.collections import Array
from std.memory import Pointer,AddressSpace,stack_allocation
from std.testing import assert_equal,assert_true
from max.gpu.host import DeviceContext
from experimental.physics_gpu.warm_seed_support import prepare_seed,patch_save,patch_restore,whole_save,whole_restore_if_needed
from experimental.physics_gpu.kernels import WORDS
from mojo_game import Vec3

def proof_patch(saved_f: Pointer[Float64,MutAnyOrigin],saved_i: Pointer[Int64,MutAnyOrigin],impulse: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],diag: Pointer[Int64,MutAnyOrigin],output: Pointer[Int64,MutAnyOrigin]):
    var shared=stack_allocation[506,DType.float64,address_space=AddressSpace.SHARED]()
    var flags=stack_allocation[32,DType.int32,address_space=AddressSpace.SHARED]()
    for i in range(506):shared[unsafe_offset=i]=Float64(i)+.125
    for i in range(32):flags[unsafe_offset=i]=Int32(i+40)
    for i in range(66):impulse[unsafe_offset=i]=Float64(i)+.25
    for i in range(130):tangent[unsafe_offset=i]=Float64(i)+.5
    for i in range(16):work[unsafe_offset=i]=Int64(i)
    for i in range(18):debug[unsafe_offset=i]=Int64(i+10)
    patch_save(shared,flags,impulse,tangent,8,4,work,debug,saved_f,saved_i)
    for i in range(506):shared[unsafe_offset=i]=-1
    for i in range(32):flags[unsafe_offset=i]=-1
    for i in range(4):impulse[unsafe_offset=9+i]=-1
    for i in range(8):tangent[unsafe_offset=17+i]=-1
    for i in range(16):work[unsafe_offset=i]+=100
    for i in range(18):debug[unsafe_offset=i]+=200
    patch_restore(shared,flags,impulse,tangent,8,4,work,debug,saved_f,saved_i,diag)
    var errors=Int64(0)
    for i in range(506):errors+=Int64(shared[unsafe_offset=i]!=Float64(i)+.125)
    for i in range(32):errors+=Int64(flags[unsafe_offset=i]!=Int32(i+40))
    for i in range(66):errors+=Int64(impulse[unsafe_offset=i]!=Float64(i)+.25)
    for i in range(130):errors+=Int64(tangent[unsafe_offset=i]!=Float64(i)+.5)
    for i in range(16):errors+=Int64(work[unsafe_offset=i]!=Int64(i))
    for i in range(18):errors+=Int64(debug[unsafe_offset=i]!=Int64(i+10))
    output[unsafe_offset=1]=errors
    # Current pressure is 1.0, disk mu*P=.2, regardless of cached normal 1000.
    for i in range(256):shared[unsafe_offset=113+i]=0
    shared[unsafe_offset=113+16]=.5
    var nn=Array[Float64,16](fill=0);nn[0]=2
    var nt=Array[Float64,32](fill=0);var qn=Array[Float64,4](fill=0);qn[0]=-2
    var old=Array[Float64,8](fill=0);var valid=Array[Bool,16](fill=False);valid[0]=True;valid[1]=True
    flags[unsafe_offset=1]=0
    tangent[unsafe_offset=7]=1000;tangent[unsafe_offset=8]=10;tangent[unsafe_offset=9]=0;tangent[unsafe_offset=10]=0
    var seed=prepare_seed(nn,nt,qn,old,shared,valid,1,.2,1e-9,Vec3(0,1,0),Vec3(1,0,0),Vec3(0,0,1),1,0,flags,tangent,diag)
    output[unsafe_offset=2]=Int64(seed.valid and seed.x[0]==.2 and seed.x[1]==0)
    var reverse=prepare_seed(nn,nt,qn,old,shared,valid,1,.2,1e-9,Vec3(0,1,0),Vec3(1,0,0),Vec3(0,0,1),-1,0,flags,tangent,diag)
    output[unsafe_offset=3]=Int64(reverse.valid and reverse.x[0]==-.2 and reverse.x[1]==0)

def initial(summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],impulse: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],projected: Pointer[Float64,MutAnyOrigin]):
    for i in range(6):summary[unsafe_offset=i]=Int32(i)
    for i in range(9):stats[unsafe_offset=i]=Float64(i)+.125
    for i in range(66):impulse[unsafe_offset=i]=Float64(i)+.25
    for i in range(130):tangent[unsafe_offset=i]=Float64(i)+.5
    for i in range(194):history[unsafe_offset=i]=Float64(i)+.75
    for i in range(1826):metrics[unsafe_offset=i]=Float64(i)+.875
    for i in range(16):work[unsafe_offset=i]=Int64(i)
    for i in range(18):debug[unsafe_offset=i]=Int64(i+10)
    for i in range(WORDS):candidate[unsafe_offset=i]=-1;projected[unsafe_offset=i]=Float64(i)+.25

def corrupt(summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],impulse: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],diag: Pointer[Int64,MutAnyOrigin]):
    for i in range(6):summary[unsafe_offset=i]=118
    for i in range(9):stats[unsafe_offset=i]=-1
    for i in range(66):impulse[unsafe_offset=i]=-1
    for i in range(130):tangent[unsafe_offset=i]=-1
    for i in range(194):history[unsafe_offset=i]=-1
    for i in range(1826):metrics[unsafe_offset=i]=-1
    for i in range(16):work[unsafe_offset=i]+=100
    for i in range(18):debug[unsafe_offset=i]+=200
    diag[unsafe_offset=9]=1

def main() raises:
    var ctx=DeviceContext()
    var sf=ctx.enqueue_create_buffer[DType.float64](520);sf.enqueue_fill(-777)
    var si=ctx.enqueue_create_buffer[DType.int64](68);si.enqueue_fill(-777)
    var wf=ctx.enqueue_create_buffer[DType.float64](2227);wf.enqueue_fill(-777)
    var wi=ctx.enqueue_create_buffer[DType.int64](42);wi.enqueue_fill(-777)
    var stats=ctx.enqueue_create_buffer[DType.float64](9)
    var impulse=ctx.enqueue_create_buffer[DType.float64](66)
    var tangent=ctx.enqueue_create_buffer[DType.float64](130)
    var history=ctx.enqueue_create_buffer[DType.float64](194)
    var metrics=ctx.enqueue_create_buffer[DType.float64](1826)
    var work=ctx.enqueue_create_buffer[DType.int64](16)
    var debug=ctx.enqueue_create_buffer[DType.int64](18)
    var diag=ctx.enqueue_create_buffer[DType.int64](66);diag.enqueue_fill(0)
    var out=ctx.enqueue_create_buffer[DType.int64](5);out.enqueue_fill(-777)
    var summary=ctx.enqueue_create_buffer[DType.int32](6)
    var retry=ctx.enqueue_create_buffer[DType.int32](3);retry.enqueue_fill(-777)
    var candidate=ctx.enqueue_create_buffer[DType.float64](WORDS)
    var projected=ctx.enqueue_create_buffer[DType.float64](WORDS)
    ctx.enqueue_function[proof_patch](sf,si,impulse,tangent,work,debug,diag,out,grid_dim=1,block_dim=1)
    ctx.synchronize()
    with out.map_to_host() as a,sf.map_to_host() as f,si.map_to_host() as i,diag.map_to_host() as d:
        assert_equal(a[0],Int64(-777));assert_equal(a[4],Int64(-777));assert_equal(a[1],Int64(0));assert_equal(a[2],Int64(1));assert_equal(a[3],Int64(1))
        assert_equal(f[0],Float64(-777));assert_equal(f[519],Float64(-777));assert_equal(i[0],Int64(-777));assert_equal(i[67],Int64(-777));assert_equal(d[6],Int64(1));assert_equal(d[3],Int64(6))
    diag.enqueue_fill(0)
    ctx.enqueue_function[initial](summary,stats,impulse,tangent,history,metrics,work,debug,candidate,projected,grid_dim=1,block_dim=1)
    ctx.enqueue_function[whole_save](summary,stats,impulse,tangent,history,metrics,work,debug,wf,wi,grid_dim=1,block_dim=1)
    ctx.enqueue_function[corrupt](summary,stats,impulse,tangent,history,metrics,work,debug,diag,grid_dim=1,block_dim=1)
    ctx.enqueue_function[whole_restore_if_needed](candidate,projected,summary,stats,impulse,tangent,history,metrics,work,debug,wf,wi,diag,retry,grid_dim=1,block_dim=1)
    ctx.synchronize()
    with stats.map_to_host() as st,impulse.map_to_host() as im,tangent.map_to_host() as ta,history.map_to_host() as hi,metrics.map_to_host() as me,work.map_to_host() as wo,debug.map_to_host() as de,candidate.map_to_host() as ca,summary.map_to_host() as su,retry.map_to_host() as re,wf.map_to_host() as f,wi.map_to_host() as i,diag.map_to_host() as d:
        for j in range(9):assert_equal(st[j],Float64(j)+.125)
        for j in range(66):assert_equal(im[j],Float64(j)+.25)
        for j in range(130):assert_equal(ta[j],Float64(j)+.5)
        for j in range(194):assert_equal(hi[j],Float64(j)+.75)
        for j in range(1826):assert_equal(me[j],Float64(j)+.875)
        for j in range(16):assert_equal(wo[j],Int64(j))
        for j in range(18):assert_equal(de[j],Int64(j+10))
        for j in range(WORDS):assert_equal(ca[j],Float64(j)+.25)
        for j in range(6):assert_equal(su[j],Int32(j))
        assert_equal(re[0],Int32(-777));assert_equal(re[2],Int32(-777));assert_equal(re[1],Int32(1));assert_equal(f[0],Float64(-777));assert_equal(f[2226],Float64(-777));assert_equal(i[0],Int64(-777));assert_equal(i[41],Int64(-777));assert_equal(d[7],Int64(1));assert_equal(d[8],Int64(118))
    print("WARM_SEED_EXACT_PATCH_AND_WHOLE_RESTORE_CURRENT_DISK_SIGN_PASS")
