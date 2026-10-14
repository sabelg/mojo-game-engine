"""Shared-worker ownership, parallel progress and per-client cancellation."""
from std.ffi import external_call
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import StreamScheduler,StreamQueue,StreamJob,TerrainConfig
from mojo_game.streaming import TERRAIN_JOB,SAVE_WORLD_JOB

def receive(mut queue: StreamQueue) raises -> StreamJob:
    for _ in range(10000):
        var job=queue.take()
        if job:return job.value().copy()
        external_call["SDL_Delay",NoneType](UInt32(1))
    raise Error("Scheduler timeout")

def main() raises:
    var scheduler=StreamScheduler(workers=4,byte_limit=64*1024*1024)
    var first=StreamQueue(scheduler=scheduler.copy())
    var second=StreamQueue(scheduler=scheduler.copy())
    var config=TerrainConfig(resolution=128)
    for i in range(4):assert_true(first.submit(StreamJob(String(i),TERRAIN_JOB,config,i,0)))
    var parallel=False
    for _ in range(2000):
        if scheduler.stats().busy>1:
            parallel=True
            break
        external_call["SDL_Delay",NoneType](UInt32(1))
    assert_true(parallel)
    first.invalidate()
    assert_true(second.submit(StreamJob("independent",TERRAIN_JOB,TerrainConfig(resolution=8))))
    first.close()
    var job=receive(second)
    assert_equal(job.key,"independent")
    assert_equal(first.pending(),0)
    assert_true(first.submit(StreamJob("restart",TERRAIN_JOB,TerrainConfig(resolution=8))))
    job=receive(first)
    assert_equal(job.key,"restart")
    second.close()
    first.close()
    assert_equal(scheduler.stats().reserved_bytes,0)
    assert_true(scheduler.stats().peak_bytes<=64*1024*1024)
    var relevant=StreamQueue(scheduler=scheduler.copy())
    assert_true(relevant.submit(StreamJob("kept",TERRAIN_JOB,TerrainConfig(resolution=8),0,0)))
    relevant.retain_terrain(1,0,4)
    job=receive(relevant)
    assert_equal(job.key,"kept")
    relevant.close()
    var bounded=StreamScheduler(workers=1,byte_limit=1024*1024,job_limit=4,save_reserve=256*1024)
    var terrain=StreamQueue(scheduler=bounded.copy())
    with assert_raises():_=terrain.submit(StreamJob("oversized",TERRAIN_JOB,TerrainConfig(resolution=128)))
    with assert_raises():_=terrain.submit(StreamJob("invalid-lod",TERRAIN_JOB,TerrainConfig(resolution=8),lod=-1))
    var saves=StreamQueue(scheduler=bounded.copy())
    for i in range(3):assert_true(terrain.submit(StreamJob(String(i),TERRAIN_JOB,TerrainConfig(resolution=8))))
    assert_true(not terrain.submit(StreamJob("full",TERRAIN_JOB,TerrainConfig(resolution=8))))
    assert_true(saves.submit(StreamJob("save",SAVE_WORLD_JOB,TerrainConfig(),path="build")))
    job=receive(saves)
    assert_equal(job.error,"")
    terrain.close()
    saves.close()
    assert_equal(bounded.stats().reserved_bytes,0)
    print("Scheduler passed: parallel workers, bounded shared reservations, isolated cancellation/restart, useful result retention")
