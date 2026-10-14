"""Bounded G05b actual GPU behavior; independent state-machine expectations."""
from std.testing import assert_equal,assert_true
from mojo_game import RigidBody3D,MassProperties3D,Vec3
from experimental.physics_gpu.sleep import GpuSleepingPhysics
from experimental.physics_gpu.lifecycle import BodyCommand

def smoke() raises:
    var s=GpuSleepingPhysics(sleep_after=.5,idle_gate=True)
    var bodies=s.submit([BodyCommand.create(RigidBody3D(MassProperties3D.sphere(2,.5)))])
    for i in range(31):
        var report=s.step(1.0/60,Vec3(0,0,0))
        assert_equal(report.asleep,Int32(1 if i==30 else 0))
        assert_equal(report.integration_calls,Int32(1));assert_equal(report.response_calls,Int32(1))
    var before=s.physics.response.normal.history.world.bodies.raw()
    var idle=s.step(1.0/60,Vec3(0,0,0));assert_true(idle.idle_skipped);assert_equal(idle.integration_calls,Int32(0));assert_equal(idle.response_calls,Int32(0))
    var after=s.physics.response.normal.history.world.bodies.raw()
    for i in range(len(before)):assert_equal(before[i],after[i])
    s.wake([bodies[0]]);var awake=s.step(1.0/60,Vec3(0,0,0));assert_equal(awake.woke,Int32(1));assert_equal(awake.asleep,Int32(0));assert_equal(awake.integration_calls,Int32(1))
    s.close();print("G05b first actual GPU: zero-gravity stationary dwell, counted idle skip, exact body preservation and explicit wake passed")
def main() raises:
    smoke();dwell_rates();support_and_islands();motion_and_forces();lifecycle_graph();contact_driven_wake();active_baseline();cpu_state_machine();failure_and_counters();response_failure_scope();actual_skip_and_capacity()
    print("G05b source sleep/wake behavior groups passed")

from std.collections import List
from std.memory import Pointer
from max.gpu import block_idx,block_dim,thread_idx
from std.testing import assert_raises
from experimental.physics_gpu.lifecycle import BodyHandle
from experimental.physics_gpu.collision import SphereCommand,BoxCommand,ShapeHandle
from experimental.physics_gpu.recommended import GpuPhysicsResponse
from experimental.physics_gpu.sleep_kernels import SLEEP_CONFIG,SLEEP_COUNTER,SLEEP_HANDLE,SLEEP_METADATA

def body(p: Vec3=Vec3(0,0,0),fixed: Bool=False,radius: Float64=.5,mass: Float64=2) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.fixed() if fixed else MassProperties3D.sphere(mass,radius),position=p)
def add_sphere(mut s: GpuSleepingPhysics,b: RigidBody3D,radius: Float64=.5) raises -> Tuple[BodyHandle,ShapeHandle]:
    var h=s.submit([BodyCommand.create(b)]);var shapes=s.submit_shapes([SphereCommand.attach(h[0],radius)]);return h[0],shapes[0]
def floor(mut s: GpuSleepingPhysics,p: Vec3=Vec3(0,-.1,0)) raises -> Tuple[BodyHandle,ShapeHandle]:
    var h=s.submit([BodyCommand.create(body(p,True))]);var shapes=s.submit_boxes([BoxCommand.attach(h[0],Vec3(5,.1,5))]);return h[0],shapes[0]
def flags(mut s: GpuSleepingPhysics,expected: List[Bool]) raises:
    var f=s.snapshot();assert_equal(len(f),len(expected))
    for i in range(len(expected)):assert_equal(f[i].asleep,expected[i])
def same(a: List[Float64],b: List[Float64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])
def quiet(mut s: GpuSleepingPhysics,gravity: Vec3=Vec3(0,0,0),frames: Int=5) raises:
    for _ in range(frames):_=s.step(1.0/60,gravity)

def dwell_rates() raises:
    # Independent rational-clock expectations: these elapsed ticks are 1/240 s.
    # No production Kahan clock, labels or eligibility outputs form the oracle.
    for hz in [30,60,120,240]:
        var s=GpuSleepingPhysics(sleep_after=.5,idle_gate=True)
        _=s.submit([BodyCommand.create(body())]);_=s.step(1.0/Float64(hz),Vec3(0,0,0))
        var elapsed_ticks=0
        for _ in range(hz//2):
            elapsed_ticks+=240//hz;var expected=elapsed_ticks>=120
            var r=s.step(1.0/Float64(hz),Vec3(0,0,0));assert_equal(r.asleep,Int32(1 if expected else 0))
            var f=s.snapshot();assert_true(abs(f[0].dwell_seconds-Float64(elapsed_ticks)/240)<=2e-15)
        var skip=s.step(1.0/Float64(hz),Vec3(0,0,0));assert_true(skip.idle_skipped);s.close()
    var mixed=GpuSleepingPhysics(sleep_after=.5,idle_gate=True);_=mixed.submit([BodyCommand.create(body())]);_=mixed.step(1.0/60,Vec3(0,0,0))
    var ticks=0
    for hz in [30,120]:
        for _ in range(6 if hz==30 else 36):
            ticks+=240//hz;var r=mixed.step(1.0/Float64(hz),Vec3(0,0,0));assert_equal(r.asleep,Int32(1 if ticks>=120 else 0))
    assert_equal(ticks,120);mixed.close()
    for threshold in [Float64(0),Float64(10)]:
        var s=GpuSleepingPhysics(sleep_after=threshold,idle_gate=True);_=s.submit([BodyCommand.create(body())]);_=s.step(1.0/60,Vec3(0,0,0))
        var r=s.step(1.0/60,Vec3(0,0,0));assert_equal(r.asleep,Int32(1 if threshold==0 else 0));s.close()
    print("G05b independent rational dwell: 30/60/120/240 Hz, mixed timesteps, zero/maximum dwell boundaries passed")

def support_and_islands() raises:
    for hz in [30,60,120]:
        var s=GpuSleepingPhysics(sleep_after=.5,idle_gate=True);_=floor(s)
        var b=body(Vec3(0,.49999,0));var pair=add_sphere(s,b)
        _=s.step(1.0/Float64(hz));_=s.step(1.0/Float64(hz));s.wake([pair[0]]);_=s.step(1.0/Float64(hz))
        for tick in range(hz//2):
            var r=s.step(1.0/Float64(hz));assert_equal(r.asleep,Int32(1 if tick==hz//2-1 else 0))
        var frozen=s.physics.response.normal.history.world.bodies.raw()
        for _ in range(4):
            var r=s.step(1.0/Float64(hz));assert_true(r.idle_skipped);assert_equal(r.integration_calls,0);assert_equal(r.response_calls,0)
            same(frozen,s.physics.response.normal.history.world.bodies.raw())
        # A fixed-only wake packet does not bridge dynamic groups.
        s.close()
    var s=GpuSleepingPhysics(sleep_after=.05,idle_gate=True);var f=floor(s)
    var a=add_sphere(s,body(Vec3(-2,.49999,0)));var b=add_sphere(s,body(Vec3(2,.49999,0)))
    quiet(s,Vec3(0,-9.81,0),8);flags(s,[True,True])
    s.wake([f[0]]);var fixed_wake=s.step(1.0/60);assert_true(fixed_wake.idle_skipped)
    s.wake([a[0]]);var report=s.step(1.0/60);flags(s,[False,True]);assert_equal(report.woke,1);assert_equal(report.integration_calls,1);assert_equal(report.response_calls,1);assert_true(not report.idle_skipped)
    quiet(s,Vec3(0,-9.81,0),6);flags(s,[True,True])
    _=s.submit([BodyCommand.update(f[0],body(Vec3(0,-.2,0),True))]);var lost=s.step(1.0/60);flags(s,[False,False]);assert_equal(lost.woke,2);assert_equal(lost.integration_calls,1);assert_equal(lost.response_calls,1);assert_true(not lost.idle_skipped)
    s.close()
    var c=GpuSleepingPhysics(sleep_after=.05,idle_gate=True)
    var ca=add_sphere(c,body());var cb=add_sphere(c,body(Vec3(1,0,0)));quiet(c);flags(c,[True,True])
    c.wake([cb[0]]);var chain=c.step(1.0/60,Vec3(0,0,0));assert_equal(chain.woke,2);flags(c,[False,False]);c.close()
    print("G05b gravity rest-to-sleep, exact frozen poses, connected wake and no shared-static wake bridge passed")

def motion_and_forces() raises:
    var fall=GpuSleepingPhysics(sleep_after=0,idle_gate=True);_=fall.submit([BodyCommand.create(body(Vec3(0,10,0)))])
    for _ in range(12):var r=fall.step(1.0/60);assert_equal(r.asleep,0);assert_equal(r.integration_calls,1)
    var raw=fall.physics.response.normal.history.world.bodies.raw();assert_true(abs(raw[12*258+1]-Float64(-1.962))<1e-10)
    fall.close()
    for angular in [False,True]:
        var s=GpuSleepingPhysics(sleep_after=0,idle_gate=True);var b=body()
        if angular:b.angular_velocity=Vec3(0,0,1e-300)
        else:b.linear_velocity=Vec3(1e-300,0,0)
        _=s.submit([BodyCommand.create(b)])
        for _ in range(5):var r=s.step(1.0/60,Vec3(0,0,0));assert_equal(r.asleep,0);assert_equal(r.integration_calls,1)
        s.close()
    var forced=GpuSleepingPhysics(sleep_after=0,idle_gate=True);var h=forced.submit([BodyCommand.create(body())]);quiet(forced);flags(forced,[True])
    for _ in range(4):
        _=forced.submit([BodyCommand.force(h[0],Vec3(5e-324,0,0))]);var r=forced.step(1.0/60,Vec3(0,0,0));assert_equal(r.asleep,0);assert_equal(r.integration_calls,1)
    var impulse=body();impulse.linear_velocity=Vec3(.1,0,0);_=forced.submit([BodyCommand.update(h[0],impulse)])
    var r=forced.step(1.0/60,Vec3(0,0,0));assert_equal(r.asleep,0);forced.close()
    print("G05b unsupported analytic free fall, subnormal-scale linear/angular motion and force/impulse intent never falsely sleep passed")

def lifecycle_graph() raises:
    var s=GpuSleepingPhysics(sleep_after=.05,idle_gate=True)
    var a=add_sphere(s,body());var b=add_sphere(s,body(Vec3(3,0,0)));quiet(s);flags(s,[True,True])
    _=s.submit([BodyCommand.update(b[0],body(Vec3(1,0,0)))]);var merge=s.step(1.0/60,Vec3(0,0,0));assert_equal(merge.woke,2);assert_equal(merge.integration_calls,1);assert_equal(merge.response_calls,1);assert_true(not merge.idle_skipped);flags(s,[False,False])
    quiet(s);flags(s,[True,True])
    _=s.submit([BodyCommand.update(b[0],body(Vec3(3,0,0)))]);var split=s.step(1.0/60,Vec3(0,0,0));assert_equal(split.woke,2);assert_equal(split.integration_calls,1);assert_equal(split.response_calls,1);assert_true(not split.idle_skipped);flags(s,[False,False])
    quiet(s);flags(s,[True,True])
    _=s.submit_shapes([SphereCommand.reshape(a[1],.6)]);var reshape=s.step(1.0/60,Vec3(0,0,0));assert_equal(reshape.woke,1);assert_equal(reshape.integration_calls,1);assert_equal(reshape.response_calls,1);assert_true(not reshape.idle_skipped);flags(s,[False,True])
    quiet(s);flags(s,[True,True]);_=s.submit_shapes([SphereCommand.detach(a[1])]);var detach=s.step(1.0/60,Vec3(0,0,0));assert_equal(detach.woke,1)
    quiet(s);_=s.submit([BodyCommand.remove(a[0])]);var removed=s.step(1.0/60,Vec3(0,0,0));assert_equal(removed.asleep,1)
    var h=s.submit([BodyCommand.create(body(Vec3(-3,0,0)))]);assert_equal(h[0].slot,a[0].slot);assert_equal(h[0].generation,a[0].generation+1)
    var reused=s.step(1.0/60,Vec3(0,0,0));flags(s,[False,True]);assert_equal(reused.asleep,1)
    with assert_raises():s.wake([h[0],a[0]])
    assert_equal(s.sleep.last_error,SLEEP_HANDLE);quiet(s);flags(s,[True,True]);s.close()
    print("G05b merge/split wakes both old/new components; reshape/detach/removal/reuse and stale wake handles passed")

def contact_driven_wake() raises:
    var s=GpuSleepingPhysics(sleep_after=.05,idle_gate=True);_=add_sphere(s,body());var b=add_sphere(s,body(Vec3(1.217,0,0)))
    quiet(s);flags(s,[True,True]);var moving=body(Vec3(1.217,0,0));moving.linear_velocity=Vec3(-1,0,0)
    _=s.submit([BodyCommand.update(b[0],moving)]);var woken=False
    for tick in range(16):
        var r=s.step(1.0/60,Vec3(0,0,0));assert_equal(r.integration_calls,1)
        if tick<12:assert_equal(r.asleep,1)
        if tick>0 and r.woke==1:woken=True;assert_equal(r.asleep,0)
    assert_true(woken);flags(s,[False,False]);s.close()
    print("G05b incoming awake-body contact wakes sleeping island with full integration path, no omitted sleeper gravity phase passed")

def active_baseline() raises:
    var s=GpuSleepingPhysics(idle_gate=True);var baseline=GpuPhysicsResponse()
    var moving=body(Vec3(0,.35,0),radius=.35,mass=1);moving.linear_velocity=Vec3(3,0,0);moving.angular_velocity=Vec3(0,0,4)
    _=add_sphere(s,moving,.35);_=floor(s)
    var h=baseline.response.normal.history.world.bodies.submit([BodyCommand.create(moving),BodyCommand.create(body(Vec3(0,-.1,0),True))])
    _=baseline.response.normal.history.world.submit_shapes([SphereCommand.attach(h[0],.35)])
    _=baseline.response.normal.history.world.submit_boxes([BoxCommand.attach(h[1],Vec3(5,.1,5))])
    for _ in range(30):
        var r=s.step(1.0/60,coefficient=.8);assert_equal(r.asleep,0);assert_equal(r.integration_calls,1);assert_equal(r.response_calls,1)
        assert_equal(baseline.response.normal.history.world.bodies.step(1.0/60),0);_=baseline.resolve(1.0/60,coefficient=.8)
        same(s.physics.response.normal.history.world.bodies.raw(),baseline.response.normal.history.world.bodies.raw())
    s.close();baseline.close();print("G05b active rolling path matches unchanged recommended stable response in every body value; no skip inferred from flags passed")

from experimental.physics_gpu.sleep_reference import SleepReference,SleepEdge

def cpu_state_machine() raises:
    var s=GpuSleepingPhysics(sleep_after=.05,idle_gate=True)
    var a=add_sphere(s,body());var b=add_sphere(s,body(Vec3(1,0,0)));_=add_sphere(s,body(Vec3(4,0,0)))
    var reference=SleepReference(3,12);var edges: List[SleepEdge]=[SleepEdge(0,1)]
    var live: List[Bool]=[True,True,True];var generations: List[Int]=[1,1,1];var eligible: List[Bool]=[True,True,True]
    for tick in range(20):
        var dirty: List[Bool]=[False,False,False]
        if tick==5:s.wake([a[0]]);dirty[0]=True
        if tick==10:
            _=s.submit([BodyCommand.update(b[0],body(Vec3(2,0,0)))]);dirty[1]=True;edges=List[SleepEdge]()
        var expected=reference.tick(edges,4,eligible,dirty,live,generations);var actual=s.step(1.0/60,Vec3(0,0,0))
        assert_equal(actual.asleep,expected.asleep);assert_equal(actual.entered_sleep,expected.entered);assert_equal(actual.woke,expected.woke);assert_equal(actual.idle_skipped,expected.idle)
        var observed=s.snapshot()
        for i in range(3):assert_equal(observed[i].asleep,reference.asleep[i]);assert_equal(observed[i].root.slot,Int32(reference.roots[i]))
    s.close();print("G05b independent CPU BFS/rational state machine matches sleep/wake/idle events and roots through connected wake/split passed")

def set_uint(words: Pointer[UInt64,MutAnyOrigin],offset: Int32,value: UInt64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def set_float(words: Pointer[Float64,MutAnyOrigin],offset: Int32,value: Float64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def dump_uint(mut s: GpuSleepingPhysics) raises -> List[UInt64]:
    var data=List[UInt64]()
    with s.sleep._state.map_to_host() as state,s.sleep._publication.map_to_host() as p,s.sleep._requests.map_to_host() as requests:
        for i in range(256*7+2):data.append(UInt64(state[i]))
        for i in range(8):data.append(UInt64(p[i]))
        for i in range(258):data.append(UInt64(Int64(requests[i])))
    return data^
def dump_clock(mut s: GpuSleepingPhysics) raises -> List[Float64]:
    var data=List[Float64]()
    with s.sleep._clock.map_to_host() as clock:
        for i in range(516):data.append(Float64(clock[i]))
    return data^
def uint_equal(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def failure_and_counters() raises:
    var s=GpuSleepingPhysics(sleep_after=0,idle_gate=True);var h=s.submit([BodyCommand.create(body())]);quiet(s);flags(s,[True])
    var old=dump_uint(s);var clocks=dump_clock(s);var bodies=s.physics.response.normal.history.world.bodies.raw()
    for invalid in [Float64(0),Float64(-1),Float64("nan"),Float64("inf"),Float64(1.0/300),Float64(.1)]:
        with assert_raises():_=s.step(invalid,Vec3(0,0,0))
        assert_equal(s.sleep.last_error,SLEEP_CONFIG);assert_equal(s.last_integration_calls,0);uint_equal(old,dump_uint(s));same(clocks,dump_clock(s));same(bodies,s.physics.response.normal.history.world.bodies.raw())
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0),coefficient=Float64("nan"))
    with assert_raises():_=s.step(1.0/60,Vec3(Float64("inf"),0,0))
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0),velocity_iterations=0)
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0),ceiling=Float64(5e-324))
    uint_equal(old,dump_uint(s));same(clocks,dump_clock(s))
    for bad in [BodyHandle(-1,1,h[0].owner),BodyHandle(h[0].slot,0,h[0].owner),BodyHandle(h[0].slot,h[0].generation,h[0].owner+1)]:
        with assert_raises():s.wake([h[0],bad])
        assert_equal(s.sleep.last_error,SLEEP_HANDLE);uint_equal(old,dump_uint(s))
    # Exact unsigned epoch boundary: MAX-1 publishes MAX once, then rejects.
    s.physics.response.normal.history.world.bodies._ctx.enqueue_function[set_uint](s.sleep._publication,Int32(1),UInt64.MAX-1,grid_dim=1,block_dim=1)
    s.physics.response.normal.history.world.bodies._ctx.synchronize();var last=s.step(1.0/60,Vec3(0,0,0));assert_equal(last.epoch,UInt64.MAX)
    var full=dump_uint(s)
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0))
    assert_equal(s.sleep.last_error,SLEEP_COUNTER);uint_equal(full,dump_uint(s));assert_equal(s.last_integration_calls,0)
    s.physics.response.normal.history.world.bodies._ctx.enqueue_function[set_uint](s.sleep._publication,Int32(1),UInt64(10),grid_dim=1,block_dim=1)
    s.physics.response.normal.history.world.bodies._ctx.synchronize()
    # Counter failure retains an explicit wake request; body/response calls are
    # earlier separate commits and are counted honestly on the failed tick.
    s.wake([h[0]])
    s.physics.response.normal.history.world.bodies._ctx.enqueue_function[set_uint](s.sleep._publication,Int32(6),UInt64.MAX,grid_dim=1,block_dim=1)
    s.physics.response.normal.history.world.bodies._ctx.synchronize();var before=dump_uint(s);var clock_before=dump_clock(s)
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0))
    assert_equal(s.sleep.last_error,SLEEP_COUNTER);uint_equal(before,dump_uint(s));same(clock_before,dump_clock(s));assert_equal(s.last_integration_calls,1);assert_equal(s.last_response_calls,1)
    s.physics.response.normal.history.world.bodies._ctx.enqueue_function[set_uint](s.sleep._publication,Int32(6),UInt64(0),grid_dim=1,block_dim=1)
    s.physics.response.normal.history.world.bodies._ctx.synchronize();var retry=s.step(1.0/60,Vec3(0,0,0));assert_equal(retry.woke,1)
    # Invalid clock data cannot manufacture sleep or consume queued intent.
    s.physics.response.normal.history.world.bodies._ctx.enqueue_function[set_float](s.sleep._clock,Int32(1),Float64("nan"),grid_dim=1,block_dim=1)
    s.physics.response.normal.history.world.bodies._ctx.synchronize();var previous=dump_uint(s)
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0))
    assert_equal(s.sleep.last_error,SLEEP_METADATA);uint_equal(previous,dump_uint(s));s.close();s.close()
    with assert_raises():_=s.snapshot()
    for invalid in [Float64(-1),Float64(10.1),Float64("nan"),Float64("inf")]:
        with assert_raises():_=GpuSleepingPhysics(sleep_after=invalid)
    print("G05b invalid config/stale mixed wake rollback, exact epoch/counter exhaustion, retained requests and corrupt dwell rejection passed")

def response_failure_scope() raises:
    var s=GpuSleepingPhysics(sleep_after=.05,idle_gate=True)
    var moving=body();moving.linear_velocity=Vec3(2,0,0)
    _=add_sphere(s,moving);_=add_sphere(s,body(Vec3(.99,0,0)));_=add_sphere(s,body(Vec3(1.98,0,0)))
    var old=dump_uint(s);var clocks=dump_clock(s);var before=s.physics.response.normal.history.world.bodies.raw()
    with assert_raises():_=s.step(1.0/60,Vec3(0,0,0),velocity_iterations=1)
    assert_equal(s.last_integration_calls,1);assert_equal(s.last_response_calls,1);assert_equal(s.physics.response.normal.last_error,55)
    uint_equal(old,dump_uint(s));same(clocks,dump_clock(s));var after=s.physics.response.normal.history.world.bodies.raw();assert_true(after[4*258+1]>before[4*258+1])
    var retry=s.step(1.0/60,Vec3(0,0,0));assert_equal(retry.epoch,UInt64(1));assert_equal(retry.integration_calls,1);s.close()
    print("G05b response rejection leaves earlier integration visible while sleep epoch/dwell/requests remain transactional; retry passed")

def actual_skip_and_capacity() raises:
    var s=GpuSleepingPhysics(sleep_after=0,idle_gate=True);_=s.submit([BodyCommand.create(body())]);quiet(s)
    s.physics.response.normal.history.world.bodies._scratch.enqueue_fill(888)
    s.physics.response.normal._candidate.enqueue_fill(777)
    s.physics.response.normal.history.world.bodies._ctx.synchronize()
    var r=s.step(1.0/60,Vec3(0,0,0));assert_true(r.idle_skipped);assert_equal(r.integration_calls,0);assert_equal(r.response_calls,0)
    with s.physics.response.normal.history.world.bodies._scratch.map_to_host() as a,s.physics.response.normal._candidate.map_to_host() as b:
        for i in range(23*258):assert_equal(a[i],Float64(888));assert_equal(b[i],Float64(777))
    s.close()
    var edited=GpuSleepingPhysics(sleep_after=0,idle_gate=True);var handles=edited.submit([BodyCommand.create(body())]);quiet(edited)
    _=edited.submit([BodyCommand.update(handles[0],body())]);var identical=edited.step(1.0/60,Vec3(0,0,0))
    assert_equal(identical.woke,1);assert_equal(identical.integration_calls,1);assert_equal(identical.response_calls,1);assert_true(not identical.idle_skipped);edited.close()
    var ungated=GpuSleepingPhysics(sleep_after=0);_=ungated.submit([BodyCommand.create(body())]);quiet(ungated)
    var full=ungated.step(1.0/60,Vec3(0,0,0));assert_equal(full.asleep,1);assert_equal(full.integration_calls,1);assert_equal(full.response_calls,1);assert_true(not full.idle_skipped);ungated.close()
    var empty=GpuSleepingPhysics(idle_gate=True);var e=empty.step(1.0/60,Vec3(0,0,0));assert_equal(e.asleep,0);assert_true(not e.idle_skipped);empty.close()
    var many=GpuSleepingPhysics(sleep_after=0,idle_gate=True);var commands=List[BodyCommand]()
    for i in range(256):commands.append(BodyCommand.create(body(Vec3(Float64(i)*2,0,0))))
    _=many.submit(commands);_=many.step(1.0/60,Vec3(0,0,0));var all_sleep=many.step(1.0/60,Vec3(0,0,0));assert_equal(all_sleep.asleep,256);assert_equal(all_sleep.entered_sleep,256)
    var skip=many.step(1.0/60,Vec3(0,0,0));assert_equal(skip.integration_calls,0);assert_equal(skip.response_calls,0);many.close()
    print("G05b untouched work-buffer canaries prove actual integration/response skipping; default gate-off, empty and 256-body event capacity passed")
