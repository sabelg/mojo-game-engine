"""Controlled GPU mapping protocol: no solver or eligibility gate is relaxed."""
from std.collections import List
from std.memory import Pointer
from std.testing import assert_equal,assert_true
from experimental.physics_gpu.warm_plumbing_response import GpuWarmPlumbingBoxResponse
from experimental.physics_gpu.warm_cache_kernels import *
from experimental.physics_gpu.shape_kernels import SHAPE_STRIDE,POISON
from experimental.physics_gpu.kernels import STRIDE,WORDS
from experimental.physics_gpu.box_box import float_bits

# Manufactured immutable solver inputs isolate correspondence from geometry.
# Body order is intentionally reversed relative to shape/solver A/B order.
def fixture(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],features: Pointer[UInt64,MutAnyOrigin],descriptors: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],dt: Pointer[Float64,MutAnyOrigin],revisions: Pointer[UInt64,MutAnyOrigin]):
    for slot in range(2):
        for f in range(23):candidate[unsafe_offset=f*STRIDE+slot+1]=0
        candidate[unsafe_offset=10*STRIDE+slot+1]=1
    candidate[unsafe_offset=1]=2;candidate[unsafe_offset=5*STRIDE+1]=1
    for f in range(1,4):candidate[unsafe_offset=f*STRIDE+1]=1
    for i in range(4):
        var h=1+i*11
        headers[unsafe_offset=h]=0;headers[unsafe_offset=h+1]=1;headers[unsafe_offset=h+2]=1;headers[unsafe_offset=h+3]=1;headers[unsafe_offset=h+4]=1
        headers[unsafe_offset=h+5]=1;headers[unsafe_offset=h+6]=1;headers[unsafe_offset=h+7]=1;headers[unsafe_offset=h+8]=0;headers[unsafe_offset=h+9]=1;headers[unsafe_offset=h+10]=123
        var x=Float64(-.5) if i%2==0 else Float64(.5);var z=Float64(-.5) if i<2 else Float64(.5);var g=1+i*10
        geometry[unsafe_offset=g]=0;geometry[unsafe_offset=g+1]=1;geometry[unsafe_offset=g+2]=0;geometry[unsafe_offset=g+3]=0
        for side in range(2):geometry[unsafe_offset=g+4+side*3]=x;geometry[unsafe_offset=g+5+side*3]=.5;geometry[unsafe_offset=g+6+side*3]=z
        impulses[unsafe_offset=1+i]=1;tangent[unsafe_offset=1+i*2]=.1;tangent[unsafe_offset=2+i*2]=.02
    spans[unsafe_offset=1]=0;spans[unsafe_offset=2]=4;features[unsafe_offset=1]=1;features[unsafe_offset=2]=0
    for slot in range(2):
        for axis in range(4,7):descriptors[unsafe_offset=axis*SHAPE_STRIDE+slot+1]=.5
    for i in range(6):summary[unsafe_offset=i]=0
    summary[unsafe_offset=3]=1;summary[unsafe_offset=4]=4
    for i in range(1,8):state[unsafe_offset=i]=0
    state[unsafe_offset=1]=1;state[unsafe_offset=6]=1;dt[unsafe_offset=1]=1.0/60;revisions[unsafe_offset=1]=0;revisions[unsafe_offset=2]=0

def save_cache(h: Pointer[UInt64,MutAnyOrigin],f: Pointer[Float64,MutAnyOrigin],p: Pointer[Float64,MutAnyOrigin],m: Pointer[UInt64,MutAnyOrigin],oh: Pointer[UInt64,MutAnyOrigin],of: Pointer[Float64,MutAnyOrigin],op: Pointer[Float64,MutAnyOrigin],om: Pointer[UInt64,MutAnyOrigin]):
    for i in range(16*WP+2):oh[unsafe_offset=i]=h[unsafe_offset=i]
    for i in range(16*WF+2):of[unsafe_offset=i]=f[unsafe_offset=i]
    for i in range(64*WPOINT+2):op[unsafe_offset=i]=p[unsafe_offset=i]
    for i in range(WMETA):om[unsafe_offset=i]=m[unsafe_offset=i]

def vary(h: Pointer[UInt64,MutAnyOrigin],f: Pointer[Float64,MutAnyOrigin],p: Pointer[Float64,MutAnyOrigin],m: Pointer[UInt64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],features: Pointer[UInt64,MutAnyOrigin],revisions: Pointer[UInt64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],mode: Int32):
    state[unsafe_offset=1]=2;state[unsafe_offset=2]=1;state[unsafe_offset=3]=1;state[unsafe_offset=4]=1;state[unsafe_offset=5]=1;state[unsafe_offset=6]=1
    if mode==1:
        for i in range(2):
            for j in range(WPOINT):
                var a=1+i*WPOINT+j;var b=1+(3-i)*WPOINT+j;var v=p[unsafe_offset=a];p[unsafe_offset=a]=p[unsafe_offset=b];p[unsafe_offset=b]=v
    elif mode==2:
        for j in range(6):p[unsafe_offset=1+WPOINT+j]=p[unsafe_offset=1+j]
    elif mode==3:features[unsafe_offset=1]=0
    elif mode==4:
        for i in range(4):geometry[unsafe_offset=2+i*10]=0;geometry[unsafe_offset=3+i*10]=1
    elif mode==5:features[unsafe_offset=2]=1
    elif mode==6:spans[unsafe_offset=2]=3
    elif mode==7:revisions[unsafe_offset=1]=1
    elif mode==10:state[unsafe_offset=5]=0
    elif mode==11:state[unsafe_offset=1]=1
    elif mode==14:
        for i in range(4):headers[unsafe_offset=3+i*11]=2
    elif mode==16:
        for i in range(4):headers[unsafe_offset=11+i*11]=456
    elif mode==17:
        for i in range(4):geometry[unsafe_offset=5+i*10]+=.2
    elif mode==18:
        for i in range(WP):h[unsafe_offset=1+WP+i]=h[unsafe_offset=1+i]
        m[unsafe_offset=1]=2
    elif mode==19:p[unsafe_offset=7]=-1
    elif mode==20:f[unsafe_offset=2]*=2
    elif mode==22:state[unsafe_offset=2]=UInt64.MAX
    elif mode==23:state[unsafe_offset=1]=UInt64.MAX;state[unsafe_offset=4]=UInt64.MAX

def immutable(mut gpu: GpuWarmPlumbingBoxResponse) raises -> List[UInt64]:
    gpu.detection.world.bodies._ctx.synchronize();var out=List[UInt64]()
    with gpu._candidate.map_to_host() as b,gpu._headers.map_to_host() as h,gpu._geometry.map_to_host() as g,gpu._spans.map_to_host() as s,gpu._impulses.map_to_host() as n,gpu._tangent.map_to_host() as t,gpu._metrics.map_to_host() as metrics:
        for i in range(WORDS):out.append(float_bits(Float64(b[i])))
        for i in range(706):out.append(UInt64(h[i]))
        for i in range(642):out.append(float_bits(Float64(g[i])))
        for i in range(34):out.append(UInt64(Int64(s[i])))
        for i in range(66):out.append(float_bits(Float64(n[i])))
        for i in range(130):out.append(float_bits(Float64(t[i])))
        for i in range(1826):out.append(float_bits(Float64(metrics[i])))
    return out^

def prepare(mut gpu: GpuWarmPlumbingBoxResponse,mu: Float64=.2,c: Float64=1,s: Float64=0,patch_cap: Int32=16,point_cap: Int32=64,dt: Float64=1.0/60) raises:
    gpu.detection.world.bodies._ctx.enqueue_function[warm_prepare](gpu._candidate,gpu._headers,gpu._geometry,gpu._spans,gpu.detection._features,gpu.detection.world._values,gpu._summary,gpu.detection.world.bodies._warm_revisions,gpu.detection.world.bodies._warm_state,gpu.detection.world.bodies._warm_dt,gpu._warm_current_h,gpu._warm_current_f,gpu._warm_current_p,gpu._warm_current_m,gpu._warm_pending_h,gpu._warm_pending_f,gpu._warm_pending_p,gpu._warm_pending_m,gpu._warm_mapping,gpu._warm_diagnostic,dt,Float64(0),mu,Int32(96),Int32(64),gpu._velocity_budget,patch_cap,point_cap,c,s,grid_dim=1,block_dim=1)

def reject(summary: Pointer[Int32,MutAnyOrigin]):
    summary[unsafe_offset=0]=55

def committed(mut gpu: GpuWarmPlumbingBoxResponse) raises -> List[UInt64]:
    gpu.detection.world.bodies._ctx.synchronize();var out=List[UInt64]()
    with gpu._warm_current_h.map_to_host() as h,gpu._warm_current_f.map_to_host() as f,gpu._warm_current_p.map_to_host() as p,gpu._warm_current_m.map_to_host() as m:
        for i in range(16*WP+2):out.append(UInt64(h[i]))
        for i in range(16*WF+2):out.append(float_bits(Float64(f[i])))
        for i in range(64*WPOINT+2):out.append(float_bits(Float64(p[i])))
        for i in range(WMETA):out.append(UInt64(m[i]))
    return out^

def main() raises:
    for feature in range(15):assert_equal(warm_feature(warm_feature(UInt64(feature),True),True),UInt64(feature))
    var gpu=GpuWarmPlumbingBoxResponse(velocity_budget=96)
    var oh=gpu.detection.world.bodies._ctx.enqueue_create_buffer[DType.uint64](16*WP+2);var of=gpu.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](16*WF+2);var op=gpu.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](64*WPOINT+2);var om=gpu.detection.world.bodies._ctx.enqueue_create_buffer[DType.uint64](WMETA)
    gpu.detection.world.bodies._ctx.enqueue_function[fixture](gpu._candidate,gpu._headers,gpu._geometry,gpu._spans,gpu.detection._features,gpu.detection.world._values,gpu._summary,gpu._impulses,gpu._tangent,gpu.detection.world.bodies._warm_state,gpu.detection.world.bodies._warm_dt,gpu.detection.world.bodies._warm_revisions,grid_dim=1,block_dim=1)
    gpu.detection.world.bodies._ctx.enqueue_function[warm_begin](gpu.detection.world.bodies._warm_state,gpu._warm_pending_m,gpu._warm_mapping,gpu._warm_diagnostic,grid_dim=1,block_dim=1)
    prepare(gpu)
    gpu.detection.world.bodies._ctx.enqueue_function[warm_publish](gpu._headers,gpu._geometry,gpu._impulses,gpu._tangent,gpu._summary,gpu.detection.world.bodies._warm_state,gpu._warm_current_h,gpu._warm_current_f,gpu._warm_current_p,gpu._warm_current_m,gpu._warm_pending_h,gpu._warm_pending_f,gpu._warm_pending_p,gpu._warm_pending_m,gpu._warm_diagnostic,Float64(1),Float64(0),Float64(.2),grid_dim=1,block_dim=1)
    gpu.detection.world.bodies._ctx.synchronize()
    with gpu._warm_current_h.map_to_host() as h,gpu._warm_current_f.map_to_host() as f,gpu._warm_current_p.map_to_host() as p,gpu._warm_current_m.map_to_host() as m:
        assert_equal(m[1],UInt64(1));assert_equal(h[4],UInt64(0));assert_equal(h[9],UInt64(1));assert_equal(h[12],UInt64(4));assert_equal(Float64(f[2]),Float64(-1))
        assert_equal(Float64(p[2]),Float64(-.5));assert_equal(Float64(p[5]),Float64(.5));assert_equal(Float64(p[7]),Float64(1));assert_equal(Float64(p[8]),Float64(.02));assert_equal(Float64(p[10]),Float64(.1))
    gpu.detection.world.bodies._ctx.enqueue_function[save_cache](gpu._warm_current_h,gpu._warm_current_f,gpu._warm_current_p,gpu._warm_current_m,oh,of,op,om,grid_dim=1,block_dim=1)
    for mode in range(24):
        gpu.detection.world.bodies._ctx.enqueue_function[save_cache](oh,of,op,om,gpu._warm_current_h,gpu._warm_current_f,gpu._warm_current_p,gpu._warm_current_m,grid_dim=1,block_dim=1)
        gpu.detection.world.bodies._ctx.enqueue_function[fixture](gpu._candidate,gpu._headers,gpu._geometry,gpu._spans,gpu.detection._features,gpu.detection.world._values,gpu._summary,gpu._impulses,gpu._tangent,gpu.detection.world.bodies._warm_state,gpu.detection.world.bodies._warm_dt,gpu.detection.world.bodies._warm_revisions,grid_dim=1,block_dim=1)
        gpu.detection.world.bodies._ctx.enqueue_function[vary](gpu._warm_current_h,gpu._warm_current_f,gpu._warm_current_p,gpu._warm_current_m,gpu._headers,gpu._geometry,gpu._spans,gpu.detection._features,gpu.detection.world.bodies._warm_revisions,gpu.detection.world.bodies._warm_state,Int32(mode),grid_dim=1,block_dim=1)
        var before=immutable(gpu)
        gpu.detection.world.bodies._ctx.enqueue_function[warm_begin](gpu.detection.world.bodies._warm_state,gpu._warm_pending_m,gpu._warm_mapping,gpu._warm_diagnostic,grid_dim=1,block_dim=1)
        prepare(gpu,mu=Float64(.3) if mode==8 else Float64(.2),c=Float64(0) if mode==12 else Float64(1),s=Float64(1) if mode==12 else Float64(0),patch_cap=Int32(0) if mode==9 else Int32(16),point_cap=Int32(3) if mode==15 else Int32(64),dt=Float64(1.0/120) if mode==13 else Float64(1.0/60))
        var after=immutable(gpu);assert_equal(len(before),len(after))
        for i in range(len(before)):assert_equal(before[i],after[i])
        var report=gpu.cache_report();assert_equal(report[13],Int64(0))
        var hit=mode==0 or mode==1 or mode==12 or mode==21;assert_equal(report[1],Int64(1 if hit else 0))
        with gpu._warm_mapping.map_to_host() as map,gpu._warm_pending_m.map_to_host() as m:
            assert_equal(map[0],Int32(-98765));assert_equal(map[65],Int32(-98765))
            for i in range(4):assert_equal(map[i+1],Int32(3-i if mode==1 else i) if hit else Int32(-1))
            if mode==9 or mode==11 or mode==13 or mode==15 or mode==5 or mode==22 or mode==23:assert_equal(m[1],UInt64(0))
        if mode==21:
            var cache=committed(gpu)
            gpu.detection.world.bodies._ctx.enqueue_function[reject](gpu._summary,grid_dim=1,block_dim=1)
            gpu.detection.world.bodies._ctx.enqueue_function[warm_publish](gpu._headers,gpu._geometry,gpu._impulses,gpu._tangent,gpu._summary,gpu.detection.world.bodies._warm_state,gpu._warm_current_h,gpu._warm_current_f,gpu._warm_current_p,gpu._warm_current_m,gpu._warm_pending_h,gpu._warm_pending_f,gpu._warm_pending_p,gpu._warm_pending_m,gpu._warm_diagnostic,Float64(1),Float64(0),Float64(.2),grid_dim=1,block_dim=1)
            var unchanged=committed(gpu);assert_equal(len(cache),len(unchanged))
            for i in range(len(cache)):assert_equal(cache[i],unchanged[i])
            assert_equal(gpu.cache_report()[12],Int64(1))
        print("WARM_MAPPING_PROTOCOL_PASS",mode,"hits",report[1],"immutable solver words",len(before))
    gpu.close()
