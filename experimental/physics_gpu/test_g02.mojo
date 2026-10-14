"""Actual G02 GPU lifecycle, atomicity, residency and CPU-oracle fixtures."""
from std.collections import List
from std.testing import assert_equal, assert_true, assert_raises
from mojo_game import RigidBody3D, MassProperties3D, Vec3
from experimental.physics_gpu.lifecycle import GpuWorld, BodyCommand, BodyHandle
from experimental.physics_gpu.lifecycle_kernels import STALE_HANDLE, HANDLE_RANGE, WRONG_WORLD, BAD_COMMAND, BAD_BODY, IMMUTABLE_MASS, WORLD_FULL
from experimental.physics_gpu.kernels import CAPACITY, STRIDE, FIELDS, SENTINEL
from experimental.physics_gpu.test import decoded, near

def packet(c: BodyCommand) -> List[BodyCommand]:
    var result: List[BodyCommand]=[c]
    return result^

def sphere(x: Float64=0) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.sphere(2,.5),position=Vec3(x,3,0))

def equal_state(a: List[Float64],b: List[Float64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def equal_meta(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def rejected(mut world: GpuWorld,commands: List[BodyCommand],code: Int32) raises:
    var state=world.raw();var meta=world.metadata()
    with assert_raises():_=world.submit(commands)
    assert_equal(world.last_error,code)
    equal_state(state,world.raw());equal_meta(meta,world.metadata())

def lifecycle() raises:
    var world=GpuWorld()
    var created=world.submit(packet(BodyCommand.create(sphere())))
    var old=created[0]
    assert_equal(old.slot,Int32(0));assert_equal(old.generation,UInt64(1));assert_true(old.owner!=0)
    var ids=world.storage_ids()
    _=world.submit(packet(BodyCommand.remove(old)))
    assert_equal(len(world.poses()),0)
    var next=world.submit(packet(BodyCommand.create(sphere(4))))
    var live=next[0]
    assert_equal(live.slot,old.slot);assert_equal(live.generation,UInt64(2));assert_equal(live.owner,old.owner)
    rejected(world,packet(BodyCommand.force(old,Vec3(999,0,0))),STALE_HANDLE)
    rejected(world,packet(BodyCommand.remove(old)),STALE_HANDLE)
    for slot in [-1,256]:
        rejected(world,packet(BodyCommand.remove(BodyHandle(Int32(slot),live.generation,live.owner))),HANDLE_RANGE)
    rejected(world,packet(BodyCommand.remove(BodyHandle(live.slot,0,live.owner))),STALE_HANDLE)
    rejected(world,packet(BodyCommand.remove(BodyHandle(live.slot,live.generation,0))),WRONG_WORLD)
    var other=GpuWorld()
    var foreign=other.submit(packet(BodyCommand.create(sphere())))
    rejected(world,packet(BodyCommand.remove(foreign[0])),WRONG_WORLD)
    other.close()
    var after=world.storage_ids();assert_equal(ids[0],after[0]);assert_equal(ids[1],after[1])
    world.close();world.close()
    with assert_raises():_=world.submit(packet(BodyCommand.remove(live)))
    with assert_raises():_=world.step(1.0/60)
    with assert_raises():_=world.poses()
    print("G02 GPU create/remove/reuse, stale/range/foreign handles and close passed")

def ordering_and_atomicity() raises:
    var world=GpuWorld()
    var commands: List[BodyCommand]=[BodyCommand.create(sphere()),BodyCommand.create(sphere(2))]
    var handles=world.submit(commands)
    var moved=sphere(10);moved.linear_velocity=Vec3(.5,0,0)
    var mixed: List[BodyCommand]=[BodyCommand.force(handles[0],Vec3(1,0,0)),BodyCommand.update(handles[0],moved),
        BodyCommand.force(handles[0],Vec3(3,0,0)),BodyCommand.remove(handles[1]),BodyCommand.create(sphere(5))]
    var reused=world.submit(mixed)
    assert_equal(reused[0].slot,handles[1].slot);assert_equal(reused[0].generation,UInt64(2))
    assert_equal(world.step(.1,Vec3(0,0,0)),0)
    moved.force=Vec3(3,0,0);_=moved.integrate(.1,Vec3(0,0,0))
    var current=decoded(world.raw(),Int(handles[0].slot))
    near(current.position.x,moved.position.x);near(current.linear_velocity.x,moved.linear_velocity.x)
    var fail: List[BodyCommand]=[BodyCommand.remove(handles[0]),BodyCommand.create(sphere(20)),BodyCommand.force(handles[0],Vec3(1,0,0))]
    rejected(world,fail,STALE_HANDLE);assert_equal(world.last_bad_command,Int32(2))
    var double: List[BodyCommand]=[BodyCommand.remove(handles[0]),BodyCommand.remove(handles[0])]
    rejected(world,double,STALE_HANDLE)
    var invalid=BodyCommand.create(sphere());invalid.data.mass=-1
    rejected(world,packet(invalid),BAD_BODY)
    var unknown=BodyCommand.remove(handles[0]);unknown.opcode=99
    rejected(world,packet(unknown),BAD_COMMAND)
    var huge=Float64(1e308)
    rejected(world,packet(BodyCommand.force(handles[0],Vec3(huge*huge,0,0))),BAD_BODY)
    var changed=RigidBody3D(MassProperties3D.sphere(3,.5))
    rejected(world,packet(BodyCommand.update(handles[0],changed)),IMMUTABLE_MASS)
    var invalid_host=sphere();invalid_host.properties.mass=-1
    with assert_raises():_=BodyCommand.create(invalid_host)
    var before=world.raw();assert_true(world.step(0)!=0);equal_state(before,world.raw())
    world.close()
    print("G02 GPU FIFO update/force ordering, mixed-batch rollback and invalid packets passed")

def capacity_and_retirement() raises:
    var world=GpuWorld()
    var commands=List[BodyCommand]()
    for i in range(CAPACITY):commands.append(BodyCommand.create(sphere(Float64(i))))
    var handles=world.submit(commands)
    assert_equal(len(handles),CAPACITY);assert_equal(len(world.poses()),CAPACITY)
    for i in range(CAPACITY):assert_equal(handles[i].slot,Int32(i))
    rejected(world,packet(BodyCommand.create(sphere())),WORLD_FULL)
    commands.append(BodyCommand.create(sphere()))
    var before=world.raw();var meta=world.metadata()
    with assert_raises():_=world.submit(commands)
    equal_state(before,world.raw());equal_meta(meta,world.metadata())
    world.close()
    var retired=GpuWorld()
    var start=retired.submit(packet(BodyCommand.create(sphere())))
    retired.test_generation(start[0].slot,UInt64.MAX)
    var max_handle=BodyHandle(start[0].slot,UInt64.MAX,start[0].owner)
    _=retired.submit(packet(BodyCommand.remove(max_handle)))
    var replacement=retired.submit(packet(BodyCommand.create(sphere())))
    assert_equal(replacement[0].slot,Int32(1))
    assert_equal(retired.metadata()[1],UInt64(2))
    rejected(retired,packet(BodyCommand.force(max_handle,Vec3(1,0,0))),STALE_HANDLE)
    retired.close()
    print("G02 GPU 256-body/command caps and generation-exhaustion retirement passed")

def residency_and_cleanup() raises:
    for hz in [30,60,120]:
        var world=GpuWorld();var cpu=sphere();cpu.linear_velocity=Vec3(.1,0,0)
        var handles=world.submit(packet(BodyCommand.create(cpu)))
        var identity=world.storage_ids();var dt=1.0/Float64(hz)
        for _ in range(hz*2):
            _=world.submit(packet(BodyCommand.all_forces(Vec3(1,0,0),Vec3(0,0,.01))))
            assert_equal(world.step(dt,ceiling=dt),0)
            cpu.force=Vec3(1,0,0);cpu.torque=Vec3(0,0,.01)
            _=cpu.integrate(dt,max_substep=dt)
        var final=decoded(world.raw(),Int(handles[0].slot))
        near(final.position.x,cpu.position.x);near(final.position.y,cpu.position.y)
        near(final.linear_velocity.x,cpu.linear_velocity.x);near(final.angular_velocity.z,cpu.angular_velocity.z)
        var after=world.storage_ids();assert_equal(identity[0],after[0]);assert_equal(identity[1],after[1])
        assert_equal(world.body_buffers_created,Int32(2))
        assert_equal(world.logical_command_bytes,Int64((hz*2+1)*216))
        var raw=world.raw()
        for f in range(FIELDS):
            assert_equal(raw[f*STRIDE],SENTINEL);assert_equal(raw[f*STRIDE+STRIDE-1],SENTINEL)
        world.close()
    for _ in range(6):
        var short=GpuWorld();var h=short.submit(packet(BodyCommand.create(sphere())))
        _=short.submit(packet(BodyCommand.remove(h[0])))
        short.close()
    print("G02 GPU persistent storage IDs, 30/60/120 CPU oracle, transfer counters and scope cleanup passed")

def main() raises:
    lifecycle();ordering_and_atomicity();capacity_and_retirement();residency_and_cleanup()
    print("G02 actual GPU lifecycle qualification passed; no contacts/friction/joints")
