"""Finite G05b actual GPU rest/sleep/idle/force/support-removal diagnostic."""
from std.testing import assert_equal,assert_true
from mojo_game import Vec3
from experimental.physics_gpu.sleep import GpuSleepingPhysics,SleepStepReport
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.test_sleep import body,floor,add_sphere,quiet,flags,same

def show(mut s: GpuSleepingPhysics,stage: String,r: SleepStepReport) raises:
    print("sleep_diagnostic",stage,"epoch",r.epoch,"asleep",r.asleep,"awake",r.awake,"entered",r.entered_sleep,"woke",r.woke,"integration_calls",r.integration_calls,"response_calls",r.response_calls,"idle_skipped",Int(r.idle_skipped))
    var members=s.snapshot()
    for m in members:print("sleep_member",m.body.slot,"generation",m.body.generation,"root",m.root.slot,"asleep",Int(m.asleep),"dwell",m.dwell_seconds)

def main() raises:
    var s=GpuSleepingPhysics(sleep_after=.05,idle_gate=True);var support=floor(s)
    var a=add_sphere(s,body(Vec3(-2,.49999,0)));_=add_sphere(s,body(Vec3(2,.49999,0)))
    var executed_integration=0;var executed_response=0;var skipped_steps=0;var steps=0
    for _ in range(6):
        var r=s.step(1.0/60);executed_integration+=Int(r.integration_calls);executed_response+=Int(r.response_calls);skipped_steps+=Int(r.idle_skipped);steps+=1
    flags(s,[True,True])
    var before=s.physics.response.normal.history.world.bodies.raw();var idle=s.step(1.0/60)
    assert_true(idle.idle_skipped);same(before,s.physics.response.normal.history.world.bodies.raw());show(s,"supported_idle_freeze",idle)
    _=s.submit([BodyCommand.force(a[0],Vec3(1,0,0))]);var forced=s.step(1.0/60);assert_equal(forced.asleep,1);assert_equal(forced.woke,1);show(s,"force_wakes_one_static_anchored_island",forced)
    _=s.submit([BodyCommand.remove(support[0])]);var removed=s.step(1.0/60);assert_equal(removed.asleep,0);assert_equal(removed.woke,1);show(s,"support_removed_all_incident_groups_awake",removed)
    executed_integration+=Int(idle.integration_calls)+Int(forced.integration_calls)+Int(removed.integration_calls)
    executed_response+=Int(idle.response_calls)+Int(forced.response_calls)+Int(removed.response_calls)
    skipped_steps+=Int(idle.idle_skipped)+Int(forced.idle_skipped)+Int(removed.idle_skipped);steps+=3
    assert_equal(steps,9);assert_equal(executed_integration,6);assert_equal(executed_response,6);assert_equal(skipped_steps,3)
    assert_true(not forced.idle_skipped and not removed.idle_skipped)
    print("sleep_diagnostic_totals","steps",steps,"integration_executed",executed_integration,"response_executed",executed_response,"idle_skipped",skipped_steps)
    s.close();print("G05b actual device diagnostic passed: idle work skipped, force isolation and removed support wake; no speedup claim")
