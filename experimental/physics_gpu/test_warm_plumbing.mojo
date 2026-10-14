"""Actual GPU seeds-disabled equivalence and cache transaction tests."""
from std.collections import List,Array
from std.memory import Pointer
from std.math import sqrt
from std.testing import assert_equal,assert_true,assert_raises
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.warm_plumbing_response import GpuWarmPlumbingBoxResponse
from experimental.physics_gpu.shared_operator_response import GpuSharedOperatorBoxResponse
from experimental.physics_gpu.test_warm_plumbing_helpers import add_box_warm_plumbing
from experimental.physics_gpu.test_shared_operator_helpers import add_box_shared_operator
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.test_box_interactions import bits_equal
from experimental.physics_gpu.box_box import float_bits
from experimental.physics_gpu.warm_cache_kernels import WP,WF,WPOINT,WMETA,warm_prepare,warm_begin,warm_key,warm_feature
from experimental.physics_gpu.shape_kernels import POISON
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse
from experimental.physics_gpu.test_box_interactions import snapshot
from experimental.physics_gpu.lifecycle import state_words,body_state
from experimental.physics_gpu.test_box_response import near

# Diagnostic snapshots do not include tracking attempts: rejection must preserve
# cache bytes while advancing attempts and clearing predecessor eligibility.
def cache_bits(mut gpu: GpuWarmPlumbingBoxResponse) raises -> List[UInt64]:
    gpu.detection.world.bodies._ctx.synchronize();var out=List[UInt64]()
    with gpu._warm_current_h.map_to_host() as h,gpu._warm_current_f.map_to_host() as f,gpu._warm_current_p.map_to_host() as p,gpu._warm_current_m.map_to_host() as m:
        assert_equal(h[0],UInt64.MAX);assert_equal(h[16*WP+1],UInt64.MAX);assert_equal(Float64(f[0]),POISON);assert_equal(Float64(f[16*WF+1]),POISON);assert_equal(Float64(p[0]),POISON);assert_equal(Float64(p[64*WPOINT+1]),POISON);assert_equal(m[0],UInt64.MAX);assert_equal(m[WMETA-1],UInt64.MAX)
        for i in range(16*WP+2):out.append(UInt64(h[i]))
        for i in range(16*WF+2):out.append(float_bits(Float64(f[i])))
        for i in range(64*WPOINT+2):out.append(float_bits(Float64(p[i])))
        for i in range(WMETA):out.append(UInt64(m[i]))
    with gpu._warm_mapping.map_to_host() as a,gpu._warm_diagnostic.map_to_host() as d:
        assert_equal(a[0],Int32(-98765));assert_equal(a[65],Int32(-98765));assert_equal(d[0],Int64(-98765));assert_equal(d[19],Int64(-98765))
    return out^

def equal_cache(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def paired(mut old: GpuSharedOperatorBoxResponse,mut new: GpuWarmPlumbingBoxResponse,dt: Float64=1.0/60,mu: Float64=.2,c: Float64=1,s: Float64=0) raises:
    var a=old.resolve(dt,coefficient=mu,velocity_iterations=96,position_iterations=64,basis_cos=c,basis_sin=s);var b=new.resolve(dt,coefficient=mu,velocity_iterations=96,position_iterations=64,basis_cos=c,basis_sin=s)
    bits_equal(old.detection.world.bodies.raw(),new.detection.world.bodies.raw());bits_equal(old.residual_history(),new.residual_history())
    var wo=old.work_report();var wn=new.work_report()
    for i in range(10):assert_equal(wo[i],wn[i])
    assert_equal(a.velocity_sweeps,b.velocity_sweeps);assert_equal(a.position_sweeps,b.position_sweeps);assert_equal(a.patches,b.patches);assert_equal(a.points,b.points)
    assert_equal(float_bits(a.normal_residual),float_bits(b.normal_residual));assert_equal(float_bits(a.tangent_residual),float_bits(b.tangent_residual));assert_equal(float_bits(a.kinetic_after),float_bits(b.kinetic_after))
    with old._impulses.map_to_host() as aa,new._impulses.map_to_host() as bb,old._tangent.map_to_host() as at,new._tangent.map_to_host() as bt,old._spans.map_to_host() as asp,new._spans.map_to_host() as bsp,old._geometry.map_to_host() as ag,new._geometry.map_to_host() as bg:
        for i in range(66):assert_equal(float_bits(Float64(aa[i])),float_bits(Float64(bb[i])))
        for i in range(130):assert_equal(float_bits(Float64(at[i])),float_bits(Float64(bt[i])))
        for i in range(34):assert_equal(asp[i],bsp[i])
        for i in range(642):assert_equal(float_bits(Float64(ag[i])),float_bits(Float64(bg[i])))
    var report=new.cache_report();assert_equal(report[13],Int64(0));_=cache_bits(new)

def tracking(mut gpu: GpuWarmPlumbingBoxResponse) raises -> List[UInt64]:
    gpu.detection.world.bodies._ctx.synchronize();var out=List[UInt64]()
    with gpu.detection.world.bodies._warm_revisions.map_to_host() as r,gpu.detection.world.bodies._warm_state.map_to_host() as s:
        assert_equal(r[0],UInt64.MAX);assert_equal(r[257],UInt64.MAX);assert_equal(s[0],UInt64.MAX);assert_equal(s[8],UInt64.MAX)
        for i in range(258):out.append(UInt64(r[i]))
        for i in range(9):out.append(UInt64(s[i]))
    return out^

def mutate_cache(h: Pointer[UInt64,MutAnyOrigin],f: Pointer[Float64,MutAnyOrigin],p: Pointer[Float64,MutAnyOrigin],mode: Int32):
    if mode==0:h[unsafe_offset=1+11]=(h[unsafe_offset=1+11]+1)%15
    elif mode==1:
        f[unsafe_offset=1]*=-1;f[unsafe_offset=2]*=-1;f[unsafe_offset=3]*=-1
    elif mode==2:
        for i in range(Int(h[unsafe_offset=1+13])):
            for axis in range(6):p[unsafe_offset=1+i*WPOINT+axis]+=100
    elif mode==3:
        # Duplicate anchor records: rejection of ambiguous correspondence.
        if h[unsafe_offset=1+13]>1:
            for axis in range(6):p[unsafe_offset=1+WPOINT+axis]=p[unsafe_offset=1+axis]
    elif mode==4:
        var count=Int(h[unsafe_offset=1+13])
        for i in range(count//2):
            for axis in range(WPOINT):
                var a=1+i*WPOINT+axis;var b=1+(count-1-i)*WPOINT+axis;var temp=p[unsafe_offset=a];p[unsafe_offset=a]=p[unsafe_offset=b];p[unsafe_offset=b]=temp

def main() raises:
    var old=GpuSharedOperatorBoxResponse(velocity_budget=96);var new=GpuWarmPlumbingBoxResponse(velocity_budget=96)
    var q=Quaternion.axis_angle(Vec3(1,2,3),.03);var extent=.5*(abs(q.rotate(Vec3(1,0,0)).y)+abs(q.rotate(Vec3(0,1,0)).y)+abs(q.rotate(Vec3(0,0,1)).y))
    var oa=add_box_shared_operator(old,Vec3(0,-.25,0),Vec3(5,.25,5),0);var na=add_box_warm_plumbing(new,Vec3(0,-.25,0),Vec3(5,.25,5),0)
    var ob=add_box_shared_operator(old,Vec3(0,extent-1e-5,0),orientation=q,v=Vec3(.02,0,.01));var nb=add_box_warm_plumbing(new,Vec3(0,extent-1e-5,0),orientation=q,v=Vec3(.02,0,.01))
    var hits=Int64(0);var ambiguous=Int64(0)
    for frame in range(8):
        assert_equal(old.detection.world.bodies.step(1.0/60),Int32(0));assert_equal(new.detection.world.bodies.step(1.0/60),Int32(0))
        var c=Float64(1) if frame<4 else Float64(0);var s=Float64(0) if frame<4 else Float64(1)
        paired(old,new,c=c,s=s);var report=new.cache_report();hits+=report[1];ambiguous+=report[15]
        print("WARM_PLUMBING_CONSECUTIVE_EXACT",frame,"diagnostics",report)
        with new._warm_current_m.map_to_host() as m,new.detection._features.map_to_host() as f:print("CACHE_COUNT_FEATURE_FLAGS",m[1],f[1],f[2])
    assert_equal(hits,Int64(0));assert_true(ambiguous>0)
    # Repeated resolve must be cold and publish an empty cache.
    paired(old,new);assert_equal(new.cache_report()[1],Int64(0))
    with new._warm_current_m.map_to_host() as m:assert_equal(m[1],UInt64(0))
    # Failed integration and rejected command batches do not advance stamps.
    var before=tracking(new);assert_true(new.detection.world.bodies.step(-1)!=0);equal_cache(before,tracking(new))
    var state=new.detection.world.bodies.raw();var body=nb.body
    with assert_raises():_=new.detection.world.bodies.submit([BodyCommand.update(nb.body_handle,body),BodyCommand.remove(BodyHandle(999,1,nb.body_handle.owner))])
    equal_cache(before,tracking(new));bits_equal(state,new.detection.world.bodies.raw())
    # Successful direct UPDATE must advance revision, including identical data.
    _=old.detection.world.bodies.submit([BodyCommand.update(ob.body_handle,body)]);_=new.detection.world.bodies.submit([BodyCommand.update(nb.body_handle,body)])
    var after=tracking(new);assert_equal(after[1+Int(nb.body_handle.slot)],before[1+Int(nb.body_handle.slot)]+1)
    assert_equal(old.detection.world.bodies.step(1.0/60),Int32(0));assert_equal(new.detection.world.bodies.step(1.0/60),Int32(0));paired(old,new);assert_equal(new.cache_report()[1],Int64(0))
    # Rejection after a committed integration preserves bytes but breaks reuse.
    assert_equal(old.detection.world.bodies.step(1.0/60),Int32(0));assert_equal(new.detection.world.bodies.step(1.0/60),Int32(0))
    var cache=cache_bits(new);state=new.detection.world.bodies.raw()
    with assert_raises():_=new.resolve(1.0/60,coefficient=Float64("nan"),velocity_iterations=96,position_iterations=64)
    equal_cache(cache,cache_bits(new));bits_equal(state,new.detection.world.bodies.raw())
    paired(old,new);assert_equal(new.cache_report()[1],Int64(0))
    # Invalid basis is another rejected response attempt, even before packing.
    cache=cache_bits(new)
    with assert_raises():_=new.resolve(1.0/60,basis_cos=Float64("nan"))
    equal_cache(cache,cache_bits(new));paired(old,new);assert_equal(new.cache_report()[1],Int64(0))
    old.close();new.close()
    # Cache capacity is independent of solver capacity; overflow stays cold.
    var cold=GpuSharedOperatorBoxResponse(velocity_budget=96);var full=GpuWarmPlumbingBoxResponse(velocity_budget=96,cache_points=0)
    _=add_box_shared_operator(cold,Vec3(0,-.25,0),Vec3(5,.25,5),0);_=add_box_warm_plumbing(full,Vec3(0,-.25,0),Vec3(5,.25,5),0)
    _=add_box_shared_operator(cold,Vec3(0,.49,0));_=add_box_warm_plumbing(full,Vec3(0,.49,0))
    assert_equal(cold.detection.world.bodies.step(1.0/60),Int32(0));assert_equal(full.detection.world.bodies.step(1.0/60),Int32(0));paired(cold,full)
    assert_true(full.cache_report()[8]>0)
    with full._warm_current_m.map_to_host() as m:assert_equal(m[1],UInt64(0))
    cold.close();full.close()
    var edge_old=GpuSharedOperatorBoxResponse(velocity_budget=96);var edge_new=GpuWarmPlumbingBoxResponse(velocity_budget=96)
    var qa=Quaternion.axis_angle(Vec3(1,2,3),.2);var qb=Quaternion.axis_angle(Vec3(-2,1,3),.55)
    var ax=qa.rotate(Vec3(1,0,0));var bx=qb.rotate(Vec3(1,0,0));var normal=ax.cross(bx);normal=normal*(1/normal.length())
    var half=Vec3(.8,.1,.1);var ra=.1*(abs(normal.dot(qa.rotate(Vec3(0,1,0))))+abs(normal.dot(qa.rotate(Vec3(0,0,1)))))
    var rb=.1*(abs(normal.dot(qb.rotate(Vec3(0,1,0))))+abs(normal.dot(qb.rotate(Vec3(0,0,1)))))
    var ea=add_box_shared_operator(edge_old,Vec3(0,0,0),half,0,orientation=qa);var en_a=add_box_warm_plumbing(edge_new,Vec3(0,0,0),half,0,orientation=qa)
    var eb=add_box_shared_operator(edge_old,normal*(ra+rb-1e-5),half,orientation=qb);var en_b=add_box_warm_plumbing(edge_new,normal*(ra+rb-1e-5),half,orientation=qb)
    var edge_models: List[OracleBox]=[ea,eb];var edge_new_models: List[OracleBox]=[en_a,en_b];var cpu=CpuCoupledBoxResponse(96)
    var edge_hits=Int64(0)
    for frame in range(8):
        assert_equal(edge_old.detection.world.bodies.step(1.0/60,normal*(-9.81)),Int32(0));assert_equal(edge_new.detection.world.bodies.step(1.0/60,normal*(-9.81)),Int32(0))
        var incoming=snapshot(edge_old.detection.world.bodies.raw(),edge_models);var expected=cpu.solve(incoming,1.0/60,0,.2,96,64)
        paired(edge_old,edge_new);var actual=snapshot(edge_new.detection.world.bodies.raw(),edge_new_models)
        for i in range(len(actual)):
            var x=state_words(body_state(actual[i].body));var y=state_words(body_state(expected.models[i].body))
            for j in range(23):near(x[j],y[j])
        var report=edge_new.cache_report();edge_hits+=report[1]
        print("WARM_EDGE_CONSECUTIVE_EXACT",frame,"diagnostics",report)
    assert_true(edge_hits>0);edge_old.close();edge_new.close()
    print("WARM_PLUMBING_TRANSACTION_PASS","seeds=0;current packing unchanged")
