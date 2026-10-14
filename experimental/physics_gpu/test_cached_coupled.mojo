"""Resolve-local cache proof, exact A/B state/work and generation/revision changes."""
from std.collections import List
from std.memory import Pointer
from std.testing import assert_equal,assert_true,assert_raises
from std.math import sqrt
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse
from experimental.physics_gpu.cached_coupled_response import GpuCachedCoupledBoxResponse
from experimental.physics_gpu.test_coupled_helpers import add_box_coupled
from experimental.physics_gpu.test_cached_helpers import add_box_cached
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.coupled_box_kernels import cross_metric
from experimental.physics_gpu.response_kernels import point,normal
from experimental.physics_gpu.friction_kernels import tangent_axes
from experimental.physics_gpu.kernels import load
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_response import bits_equal,near
from experimental.physics_gpu.test_box_interactions import snapshot
from experimental.physics_gpu.box_box import float_bits
from experimental.physics_gpu.shape_kernels import POISON

def reassemble(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],c: Float64,s: Float64,output: Pointer[Float64,MutAnyOrigin]):
    for i in range(1536):output[unsafe_offset=i+1]=0
    for patch in range(Int(summary[unsafe_offset=3])):
        var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var h=1+start*11
        var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]));var n=normal(geometry,start);var basis=tangent_axes(n,c,s);var t=basis[0];var u=basis[1];var base=1+patch*96
        for i in range(count):
            var p=point(geometry,start+i)
            for j in range(count):
                var q=point(geometry,start+j)
                output[unsafe_offset=base+i*8+2*j]=cross_metric(a,b,p,n,q,t);output[unsafe_offset=base+i*8+2*j+1]=cross_metric(a,b,p,n,q,u)
                output[unsafe_offset=base+32+(2*i)*8+2*j]=cross_metric(a,b,p,t,q,t);output[unsafe_offset=base+32+(2*i)*8+2*j+1]=cross_metric(a,b,p,t,q,u)
                output[unsafe_offset=base+32+(2*i+1)*8+2*j]=cross_metric(a,b,p,u,q,t);output[unsafe_offset=base+32+(2*i+1)*8+2*j+1]=cross_metric(a,b,p,u,q,u)

def main() raises:
    var old=GpuCoupledBoxResponse(velocity_budget=96);var new=GpuCachedCoupledBoxResponse(velocity_budget=96)
    var a: List[OracleBox]=[add_box_coupled(old,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_coupled(old,Vec3(0,.49,0),v=Vec3(.2,-1,.03))]
    var b: List[OracleBox]=[add_box_cached(new,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_cached(new,Vec3(0,.49,0),v=Vec3(.2,-1,.03))]
    var reference=new.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](1538);reference.enqueue_fill(POISON);var previous=List[Float64]()
    for variant in range(9):
        var half=Float64(.4) if variant>=4 and variant<8 else Float64(.5);var mass=Float64(3) if variant>=2 and variant<8 else Float64(4) if variant==8 else Float64(2)
        var orientation=Quaternion.axis_angle(Vec3(0,1,0),.02) if variant>=3 and variant<8 else Quaternion();var position=Vec3(0,Float64(2) if variant==5 else half-.01,0)
        var body=RigidBody3D(MassProperties3D.box(mass,Vec3(half,half,half)*2) if variant==2 or variant==8 else a[1].body.properties,position=position,orientation=orientation);body.linear_velocity=Vec3(.2,-1,.03)
        if variant==4:
            var local=Quaternion.axis_angle(Vec3(0,1,0),.01)
            _=old.detection.world.submit_boxes([BoxCommand.reshape(a[1].shape,Vec3(half,half,half),orientation=local)]);_=new.detection.world.submit_boxes([BoxCommand.reshape(b[1].shape,Vec3(half,half,half),orientation=local)])
            a[1].half_extents=Vec3(half,half,half);b[1].half_extents=a[1].half_extents;a[1].orientation=local;b[1].orientation=local;a[1].revision+=1;b[1].revision+=1
        if variant==2 or variant==8:
            if variant==2:
                var unchanged=new.detection.world.bodies.raw();var mass_meta=new.detection.world.bodies.metadata()
                with assert_raises():_=new.detection.world.bodies.submit([BodyCommand.update(b[1].body_handle,body)])
                assert_equal(new.detection.world.bodies.last_error,Int32(15));bits_equal(unchanged,new.detection.world.bodies.raw());var after_mass=new.detection.world.bodies.metadata()
                for i in range(len(mass_meta)):assert_equal(mass_meta[i],after_mass[i])
            var dead_a=a[1];var dead_b=b[1]
            _=old.detection.world.bodies.submit([BodyCommand.remove(dead_a.body_handle)]);_=new.detection.world.bodies.submit([BodyCommand.remove(dead_b.body_handle)])
            var before=new.detection.world.bodies.raw();var meta=new.detection.world.bodies.metadata()
            with assert_raises():_=new.detection.world.bodies.submit([BodyCommand.update(dead_b.body_handle,body)])
            bits_equal(before,new.detection.world.bodies.raw());var after_meta=new.detection.world.bodies.metadata()
            for i in range(len(meta)):assert_equal(meta[i],after_meta[i])
            _=old.detection.detect();_=new.detection.detect()
            a[1]=add_box_coupled(old,position,mass=mass,v=body.linear_velocity);b[1]=add_box_cached(new,position,mass=mass,v=body.linear_velocity)
            assert_equal(a[1].body_handle.generation,dead_a.body_handle.generation+1);assert_equal(b[1].body_handle.generation,dead_b.body_handle.generation+1);assert_equal(b[1].shape.generation,dead_b.shape.generation+1)
        else:
            a[1].body=body;b[1].body=body;_=old.detection.world.bodies.submit([BodyCommand.update(a[1].body_handle,body)]);_=new.detection.world.bodies.submit([BodyCommand.update(b[1].body_handle,body)])
        var c=Float64(1) if variant==0 or variant>=3 and variant<=5 or variant==8 else sqrt(Float64(.5)) if variant==1 or variant==2 else Float64(0)
        var s=Float64(0) if variant==0 or variant>=3 and variant<=5 or variant==8 else sqrt(Float64(.5)) if variant==1 or variant==2 else Float64(1)
        var mu=Float64(0) if variant==7 else Float64(.4) if variant==6 else Float64(.2)
        var entry=old.detection.world.bodies.raw();bits_equal(entry,new.detection.world.bodies.raw())
        var ro=old.resolve(1.0/60,coefficient=mu,velocity_iterations=96,position_iterations=64,basis_cos=c,basis_sin=s);var rn=new.resolve(1.0/60,coefficient=mu,velocity_iterations=96,position_iterations=64,basis_cos=c,basis_sin=s)
        bits_equal(old.detection.world.bodies.raw(),new.detection.world.bodies.raw());bits_equal(old.residual_history(),new.residual_history())
        var wo=old.work_report();var wn=new.work_report()
        for i in range(10):assert_equal(wo[i],wn[i])
        assert_equal(float_bits(ro.normal_residual),float_bits(rn.normal_residual));assert_equal(float_bits(ro.tangent_residual),float_bits(rn.tangent_residual));assert_equal(float_bits(ro.kinetic_after),float_bits(rn.kinetic_after));assert_equal(ro.velocity_sweeps,rn.velocity_sweeps)
        var cpu=CpuCoupledBoxResponse(96);var expected=cpu.solve(a,1.0/60,0,mu,96,64);var actual=snapshot(new.detection.world.bodies.raw(),b)
        for i in range(len(actual)):
            var x=state_words(body_state(actual[i].body));var y=state_words(body_state(expected.models[i].body))
            for j in range(23):near(x[j],y[j])
        with new._candidate.map_to_host() as candidate,new._projected.map_to_host() as projected:
            for field in range(11):
                for slot in range(2):assert_equal(float_bits(Float64(candidate[field*258+slot+1])),float_bits(Float64(projected[field*258+slot+1])))
        with new._metrics.map_to_host() as values:assert_equal(Float64(values[0]),POISON);assert_equal(Float64(values[1537]),POISON)
        if mu>0:
            new.detection.world.bodies._ctx.enqueue_function[reassemble](new._candidate,new._headers,new._geometry,new._spans,new._summary,c,s,reference,grid_dim=1,block_dim=1);new.detection.world.bodies._ctx.synchronize()
            var cache=List[Float64]();var recreated=List[Float64]()
            with new._metrics.map_to_host() as values,reference.map_to_host() as gold:
                for i in range(1538):cache.append(Float64(values[i]));recreated.append(Float64(gold[i]))
            bits_equal(cache,recreated)
            if variant>0:
                var different=False
                for i in range(1538):different=different or float_bits(cache[i])!=float_bits(previous[i])
                assert_true(different)
            previous=cache.copy()
        print("CACHE_MUTATION_EXACT",variant,"patches",rn.patches,"work",wn[3],"all active blocks/padding/canaries and unchanged geometry fields")
    var before=new.detection.world.bodies.raw();var metadata=new.detection.world.bodies.metadata()
    with assert_raises():_=new.detection.world.bodies.submit([BodyCommand.update(a[1].body_handle,a[1].body)])
    with assert_raises():_=new.resolve(1.0/60,coefficient=.2,velocity_iterations=96,position_iterations=64,basis_cos=Float64("nan"))
    with assert_raises():_=new.resolve(1.0/60,coefficient=Float64("nan"),velocity_iterations=96,position_iterations=64)
    bits_equal(before,new.detection.world.bodies.raw());var next=new.detection.world.bodies.metadata()
    for i in range(len(metadata)):assert_equal(metadata[i],next[i])
    old.close();new.close();print("CACHE_PROOF_EXACT9 cases: postprojection geometry fixed, changed basis/mass/pose/revision/material/zero contacts/mu0/generation; stale/foreign/invalid byte rollback")
