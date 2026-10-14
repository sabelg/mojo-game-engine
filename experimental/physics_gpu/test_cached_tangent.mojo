"""Resolve-local cache proof, exact A/B state/work and generation/revision changes."""
from std.collections import List
from std.memory import Pointer
from std.testing import assert_equal,assert_true,assert_raises
from std.math import sqrt
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse
from experimental.physics_gpu.cached_tangent_response import GpuCachedTangentBoxResponse as GpuCachedCoupledBoxResponse
from experimental.physics_gpu.test_coupled_helpers import add_box_coupled
from experimental.physics_gpu.test_cached_tangent_helpers import add_box_cached_tangent as add_box_cached
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.coupled_box_kernels import cross_metric
from experimental.physics_gpu.response_kernels import point,normal
from experimental.physics_gpu.friction_kernels import tangent_axes,tangent_metric
from experimental.physics_gpu.kernels import load
from experimental.physics_gpu.lifecycle import BodyCommand,body_state,state_words
from experimental.physics_gpu.collision import BoxCommand
from experimental.physics_gpu.test_box_response import bits_equal,near
from experimental.physics_gpu.test_box_interactions import snapshot
from experimental.physics_gpu.box_box import float_bits
from experimental.physics_gpu.shape_kernels import POISON

def reassemble(candidate: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],spans: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],c: Float64,s: Float64,output: Pointer[Float64,MutAnyOrigin]):
    for i in range(1824):output[unsafe_offset=i+1]=0
    for i in range(384):output[unsafe_offset=1826+i]=0
    for patch in range(Int(summary[unsafe_offset=3])):
        var start=Int(spans[unsafe_offset=1+patch*2]);var count=Int(spans[unsafe_offset=2+patch*2]);var h=1+start*11
        var a=load(candidate,Int(headers[unsafe_offset=h+3]));var b=load(candidate,Int(headers[unsafe_offset=h+8]));var n=normal(geometry,start);var basis=tangent_axes(n,c,s);var t=basis[0];var u=basis[1];var base=1+patch*96
        var basis_base=1537+patch*6
        output[unsafe_offset=basis_base]=t.x;output[unsafe_offset=basis_base+1]=t.y;output[unsafe_offset=basis_base+2]=t.z
        output[unsafe_offset=basis_base+3]=u.x;output[unsafe_offset=basis_base+4]=u.y;output[unsafe_offset=basis_base+5]=u.z
        for i in range(count):
            var p=point(geometry,start+i)
            # Independently repeat the original per-point basis and metric calls.
            var point_basis=tangent_axes(normal(geometry,start+i),c,s);var metric=tangent_metric(a,b,p,point_basis[0],point_basis[1]);var mb=1633+(start+i)*3
            output[unsafe_offset=mb]=metric.x;output[unsafe_offset=mb+1]=metric.y;output[unsafe_offset=mb+2]=metric.z
            var pb=1826+(start+i)*6
            output[unsafe_offset=pb]=point_basis[0].x;output[unsafe_offset=pb+1]=point_basis[0].y;output[unsafe_offset=pb+2]=point_basis[0].z
            output[unsafe_offset=pb+3]=point_basis[1].x;output[unsafe_offset=pb+4]=point_basis[1].y;output[unsafe_offset=pb+5]=point_basis[1].z
            for j in range(count):
                var q=point(geometry,start+j)
                output[unsafe_offset=base+i*8+2*j]=cross_metric(a,b,p,n,q,t);output[unsafe_offset=base+i*8+2*j+1]=cross_metric(a,b,p,n,q,u)
                output[unsafe_offset=base+32+(2*i)*8+2*j]=cross_metric(a,b,p,t,q,t);output[unsafe_offset=base+32+(2*i)*8+2*j+1]=cross_metric(a,b,p,t,q,u)
                output[unsafe_offset=base+32+(2*i+1)*8+2*j]=cross_metric(a,b,p,u,q,t);output[unsafe_offset=base+32+(2*i+1)*8+2*j+1]=cross_metric(a,b,p,u,q,u)

def main() raises:
    var old=GpuCoupledBoxResponse(velocity_budget=96);var new=GpuCachedCoupledBoxResponse(velocity_budget=96)
    var a: List[OracleBox]=[add_box_coupled(old,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_coupled(old,Vec3(0,.49,0),v=Vec3(.2,-1,.03))]
    var b: List[OracleBox]=[add_box_cached(new,Vec3(0,-.25,0),Vec3(5,.25,5),0),add_box_cached(new,Vec3(0,.49,0),v=Vec3(.2,-1,.03))]
    var reference=new.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](2212);reference.enqueue_fill(POISON);var previous=List[Float64]()
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
        with new._metrics.map_to_host() as values:assert_equal(Float64(values[0]),POISON);assert_equal(Float64(values[1825]),POISON)
        if mu>0:
            new.detection.world.bodies._ctx.enqueue_function[reassemble](new._candidate,new._headers,new._geometry,new._spans,new._summary,c,s,reference,grid_dim=1,block_dim=1);new.detection.world.bodies._ctx.synchronize()
            var cache=List[Float64]();var recreated=List[Float64]()
            with new._metrics.map_to_host() as values,reference.map_to_host() as gold:
                for i in range(1826):cache.append(Float64(values[i]));recreated.append(Float64(gold[i]))
            bits_equal(cache,recreated)
            with new._metrics.map_to_host() as values,reference.map_to_host() as gold,new._spans.map_to_host() as spans,new._summary.map_to_host() as summary:
                for patch in range(Int(summary[3])):
                    for j in range(Int(spans[2+patch*2])):
                        var point_index=Int(spans[1+patch*2])+j
                        for axis in range(6):assert_equal(float_bits(Float64(values[1537+patch*6+axis])),float_bits(Float64(gold[1826+point_index*6+axis])))
                assert_equal(Float64(gold[2211]),POISON)
            if variant>0:
                var different=False
                for i in range(1826):different=different or float_bits(cache[i])!=float_bits(previous[i])
                assert_true(different)
            previous=cache.copy()
        print("TANGENT_CACHE_MUTATION_EXACT",variant,"patches",rn.patches,"work",wn[3],"all active blocks/padding/canaries and unchanged geometry fields")
    var before=new.detection.world.bodies.raw();var metadata=new.detection.world.bodies.metadata()
    with assert_raises():_=new.detection.world.bodies.submit([BodyCommand.update(a[1].body_handle,a[1].body)])
    with assert_raises():_=new.resolve(1.0/60,coefficient=.2,velocity_iterations=96,position_iterations=64,basis_cos=Float64("nan"))
    with assert_raises():_=new.resolve(1.0/60,coefficient=Float64("nan"),velocity_iterations=96,position_iterations=64)
    bits_equal(before,new.detection.world.bodies.raw());var next=new.detection.world.bodies.metadata()
    for i in range(len(metadata)):assert_equal(metadata[i],next[i])
    old.close();new.close()
    var old2=GpuCoupledBoxResponse(velocity_budget=96);var new2=GpuCachedCoupledBoxResponse(velocity_budget=96)
    _=add_box_coupled(old2,Vec3(0,-.25,0),Vec3(5,.25,5),0);_=add_box_cached(new2,Vec3(0,-.25,0),Vec3(5,.25,5),0)
    for i in range(2):
        var p=Vec3(Float64(0) if i==0 else Float64(.03),.5+Float64(i)-Float64(i+1)*1e-5,0)
        _=add_box_coupled(old2,p,v=Vec3(.3,0,.05));_=add_box_cached(new2,p,v=Vec3(.3,0,.05))
    assert_equal(old2.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0));assert_equal(new2.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0))
    var ro=old2.resolve(1.0/30,coefficient=.2,velocity_iterations=96,position_iterations=64);var rn=new2.resolve(1.0/30,coefficient=.2,velocity_iterations=96,position_iterations=64);assert_equal(rn.patches,Int32(2));assert_equal(rn.points,Int32(8))
    bits_equal(old2.detection.world.bodies.raw(),new2.detection.world.bodies.raw());bits_equal(old2.residual_history(),new2.residual_history());assert_equal(float_bits(ro.tangent_residual),float_bits(rn.tangent_residual))
    var ref2=new2.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](2212);ref2.enqueue_fill(POISON)
    new2.detection.world.bodies._ctx.enqueue_function[reassemble](new2._candidate,new2._headers,new2._geometry,new2._spans,new2._summary,Float64(1),Float64(0),ref2,grid_dim=1,block_dim=1);new2.detection.world.bodies._ctx.synchronize()
    with new2._metrics.map_to_host() as values,ref2.map_to_host() as gold,new2._spans.map_to_host() as spans:
        for i in range(1826):assert_equal(float_bits(Float64(values[i])),float_bits(Float64(gold[i])))
        for patch in range(2):
            for j in range(Int(spans[2+patch*2])):
                var index=Int(spans[1+patch*2])+j
                for axis in range(6):assert_equal(float_bits(Float64(values[1537+patch*6+axis])),float_bits(Float64(gold[1826+index*6+axis])))
        assert_equal(Float64(gold[2211]),POISON)
    old2.close();new2.close();print("TANGENT_CACHE_MULTIPATCH_EXACT all8 point bases/metrics, spans and original residual/work order")
    print("TANGENT_CACHE_PROOF_EXACT9 cases: postprojection geometry fixed, changed basis/mass/pose/revision/material/zero contacts/mu0/generation; stale/foreign/invalid byte rollback")
