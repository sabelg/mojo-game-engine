"""Committed tracker tests: direct registry calls, rejection, and no wrapping."""
from std.collections import List
from std.memory import Pointer
from std.testing import assert_equal,assert_true,assert_raises
from mojo_game import Vec3,RigidBody3D,MassProperties3D
from experimental.physics_gpu.warm_lifecycle import GpuWarmWorld
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.test_box_response import bits_equal
from experimental.physics_gpu.box_box import float_bits

# Test-only bounded setup of otherwise unreachable exhaustion states.
def limit(revisions: Pointer[UInt64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],kind: Int32):
    state[unsafe_offset=6]=1
    if kind==0:state[unsafe_offset=1]=UInt64.MAX
    else:revisions[unsafe_offset=1]=UInt64.MAX

def stamps(mut world: GpuWarmWorld) raises -> List[UInt64]:
    world._ctx.synchronize();var out=List[UInt64]()
    with world._warm_revisions.map_to_host() as r,world._warm_state.map_to_host() as s,world._warm_dt.map_to_host() as d:
        assert_equal(r[0],UInt64.MAX);assert_equal(r[257],UInt64.MAX);assert_equal(s[0],UInt64.MAX);assert_equal(s[8],UInt64.MAX)
        for i in range(258):out.append(UInt64(r[i]))
        for i in range(9):out.append(UInt64(s[i]))
        for i in range(3):out.append(float_bits(Float64(d[i])))
    return out^

def same(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def main() raises:
    var world=GpuWarmWorld();var body=RigidBody3D(MassProperties3D.box(2,Vec3(1,1,1)))
    var handles=world.submit([BodyCommand.create(body),BodyCommand.create(body)])
    var before=stamps(world);var raw=world.raw()
    with assert_raises():_=world.submit([BodyCommand.update(handles[0],body),BodyCommand.remove(BodyHandle(999,1,handles[0].owner))])
    same(before,stamps(world));bits_equal(raw,world.raw())
    _=world.submit([BodyCommand.update(handles[0],body),BodyCommand.update(handles[0],body)])
    var after=stamps(world);assert_equal(after[1],UInt64(2));assert_equal(after[2],UInt64(0))
    _=world.submit([BodyCommand.force(handles[0],Vec3(1,2,3))]);same(after,stamps(world))
    raw=world.raw();assert_true(world.step(-1)!=0);same(after,stamps(world));bits_equal(raw,world.raw())
    assert_equal(world.step(1.0/60,Vec3(0,0,0)),Int32(0));after=stamps(world);assert_equal(after[259],UInt64(1));assert_equal(after[268],float_bits(Float64(1.0/60)))
    world._ctx.enqueue_function[limit](world._warm_revisions,world._warm_state,Int32(0),grid_dim=1,block_dim=1)
    assert_equal(world.step(1.0/60,Vec3(0,0,0)),Int32(0));after=stamps(world);assert_equal(after[259],UInt64.MAX);assert_equal(after[264],UInt64(0))
    world._ctx.enqueue_function[limit](world._warm_revisions,world._warm_state,Int32(1),grid_dim=1,block_dim=1)
    body.linear_velocity=Vec3(.3,0,0);_=world.submit([BodyCommand.update(handles[0],body)])
    after=stamps(world);assert_equal(after[1],UInt64.MAX);assert_equal(after[264],UInt64(0));raw=world.raw();assert_equal(raw[11*258+1],Float64(.3))
    world.close()
    with assert_raises():_=world.step(1.0/60)
    print("WARM_TRACKING_COMMITTED_PASS","batch rejection,2UPDATEs,force,failed step,dt,epoch/revision exhaustion;no wrapping or physics rejection")
