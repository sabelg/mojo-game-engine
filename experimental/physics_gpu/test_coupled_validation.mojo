"""Actual-device coupled derivative/rank and transaction failure qualification."""
from std.collections import Array,List
from std.memory import Pointer
from std.math import sqrt
from std.testing import assert_true,assert_equal,assert_raises
from std.sys import argv
from mojo_game import Vec3,RigidBody3D,MassProperties3D
from experimental.physics_gpu.lifecycle import GpuWorld,BodyCommand
from experimental.physics_gpu.coupled_friction_math import evaluate_coupled,linear8
from experimental.physics_gpu.coupled_box_response import GpuCoupledBoxResponse
from experimental.physics_gpu.test_coupled_helpers import add_box_coupled
from experimental.physics_gpu.test_box_response import near,bits_equal
from experimental.physics_gpu.box_response_math import mask_operators

def math_kernel(output: Pointer[Float64,MutAnyOrigin]):
    var nn=Array[Float64,16](fill=0);nn[0]=1
    var nt=Array[Float64,32](fill=0);nt[0]=.2;nt[1]=.1
    var tt=Array[Float64,64](fill=0);tt[0]=2;tt[1]=.3;tt[8]=.3;tt[9]=1
    var cached=mask_operators(nn,1);var qn=Array[Float64,4](fill=0);qn[0]=-1
    for kind in range(5):
        var qt=Array[Float64,8](fill=0);qt[0]=Float64(0) if kind==0 else Float64(.02) if kind==1 else Float64(2)
        qt[1]=Float64(.03) if kind==1 else Float64(.4)
        var x=Array[Float64,8](fill=0);x[0]=.01;x[1]=-.02
        var mu=Float64(0) if kind==0 else Float64(.5) if kind==1 else Float64(.2)
        if kind==3:qn[0]=1
        if kind==4:qn[0]=0;nt[0]=0;nt[1]=0
        var f=evaluate_coupled(nn,nt,tt,cached.values,cached.valid,qn,qt,x,1,mu,1e-9,True)
        output[unsafe_offset=kind*8]=1 if f.valid else 0
        output[unsafe_offset=kind*8+1]=f.pressure[0]
        for j in range(2):
            var plus=x.copy();var minus=x.copy();plus[j]+=1e-6;minus[j]-=1e-6
            var fp=evaluate_coupled(nn,nt,tt,cached.values,cached.valid,qn,qt,plus,1,mu,1e-9,False)
            var fm=evaluate_coupled(nn,nt,tt,cached.values,cached.valid,qn,qt,minus,1,mu,1e-9,False)
            for i in range(2):output[unsafe_offset=kind*8+2+i*2+j]=abs(f.jacobian[i*8+j]-(fp.residual[i]-fm.residual[i])/2e-6)
        output[unsafe_offset=kind*8+6]=sqrt((x[0]-f.residual[0])**2+(x[1]-f.residual[1])**2)
        output[unsafe_offset=kind*8+7]=mu*f.pressure[0]
    var h=Array[Float64,64](fill=0);var rhs=Array[Float64,8](fill=0);h[0]=1;h[1]=1;h[8]=1;h[9]=1;rhs[0]=2;rhs[1]=2
    var singular=linear8(h,rhs,2);output[unsafe_offset=40]=Float64(singular.rank);output[unsafe_offset=41]=singular.value[0];output[unsafe_offset=42]=singular.value[1]
    h[0]=1;h[1]=0;h[8]=0;h[9]=1e-16;rhs[0]=1;rhs[1]=0
    var conditioned=linear8(h,rhs,2);output[unsafe_offset=43]=Float64(conditioned.rank);output[unsafe_offset=44]=conditioned.value[0];output[unsafe_offset=45]=conditioned.value[1]

def math_checks() raises:
    var w=GpuWorld();var output=w._ctx.enqueue_create_buffer[DType.float64](47);output.enqueue_fill(-1234567)
    w._ctx.enqueue_function[math_kernel](output,grid_dim=1,block_dim=1);w._ctx.synchronize()
    var largest=Float64(0)
    with output.map_to_host() as values:
        for kind in range(5):
            assert_equal(Float64(values[kind*8]),Float64(1))
            for j in range(4):largest=max(largest,Float64(values[kind*8+2+j]));assert_true(Float64(values[kind*8+2+j])<1e-7)
            assert_true(Float64(values[kind*8+6])<=Float64(values[kind*8+7])+1e-12*(1+Float64(values[kind*8+7])))
        assert_equal(Float64(values[40]),Float64(1));near(Float64(values[41]),1);near(Float64(values[42]),1)
        assert_equal(Float64(values[43]),Float64(1));near(Float64(values[44]),1);near(Float64(values[45]),0);assert_equal(Float64(values[46]),Float64(-1234567))
    w.close();print("COUPLED_MATH passed: interior/sliding/zero-radius/active-normal/zero-load analytic Jacobians versus central differences; singular least norm and rank cutoff; max derivative error",largest)

def failure_checks() raises:
    for kind in range(8):
        var r=GpuCoupledBoxResponse(capacity=Int32(0 if kind==0 else 64),velocity_budget=96)
        _=add_box_coupled(r,Vec3(0,-.25,0),Vec3(5,.25,5),0)
        var body=add_box_coupled(r,Vec3(0,.5-1e-5,0),mass=Float64(.05) if kind==6 else Float64(2),v=Vec3(.3,0,.05))
        _=add_box_coupled(r,Vec3(.03,1.5-2e-5,0),v=Vec3(.3,0,.05))
        assert_equal(r.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0))
        var before=r.detection.world.bodies.raw();var meta=r.detection.world.bodies.metadata()
        with assert_raises():
            _=r.resolve(.1 if kind==2 else Float64("nan") if kind==3 else 1.0/30,coefficient=Float64("nan") if kind==4 else .2,velocity_iterations=Int32(1 if kind==1 else 97 if kind==5 else 96),position_iterations=64,basis_cos=Float64("nan") if kind==7 else 1)
        bits_equal(before,r.detection.world.bodies.raw());var after_meta=r.detection.world.bodies.metadata()
        for i in range(len(meta)):assert_equal(meta[i],after_meta[i])
        assert_equal(r.last_error,Int32(110 if kind==0 else 114 if kind==1 else 117 if kind==6 else 111))
        var work=r.work_report()
        assert_true(work[3]<=8*work[0]);assert_true(work[6]<=16*work[3]);assert_equal(work[0],work[1]+work[2]);assert_true(work[4]<=work[0]*2+work[3]+work[6]);assert_true(work[8]<=8)
        print("COUPLED_FAILURE",kind,"code",r.last_error,"attempts",work[0],"fallbacks",work[2],"Newton",work[3],"line_search",work[6],"exact body/meta rollback")
        r.close()

def main() raises:
    var a=argv()
    if a[1]=="math":math_checks()
    else:failure_checks()
