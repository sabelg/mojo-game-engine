"""Separate atomic four-interval planar-floor owner; no optimized owner imports."""
from std.collections import List,Array
from max.gpu.host import DeviceBuffer
from mojo_game import Vec3
from .collision import GpuCollisionWorld,SphereCommand
from .kernels import WORDS,SENTINEL
from .unilateral_temporal_floor_friction_kernels import unilateral_temporal_floor_friction,commit_temporal

struct GpuUnilateralTemporalFloorFrictionAdvance(Movable):
    var world: GpuCollisionWorld
    var _candidate: DeviceBuffer[DType.float64]
    var _summary: DeviceBuffer[DType.int32]
    var _stats: DeviceBuffer[DType.float64]
    var _group: DeviceBuffer[DType.float64]
    var _episode: DeviceBuffer[DType.uint64]
    var _pending_episode: DeviceBuffer[DType.uint64]
    var _last: DeviceBuffer[DType.float64]
    var _pending_last: DeviceBuffer[DType.float64]
    var _closed: Bool
    var last_error: Int32
    var _block_input: DeviceBuffer[DType.float64]
    var _block_output: DeviceBuffer[DType.float64]
    var _stop_budget: Int32
    var _segment_budget: Int32
    var _order: Int32

    def __init__(out self,point_order: Int32=0,stop_budget: Int32=4,segment_budget: Int32=6) raises:
        if point_order<0 or point_order>=24:raise Error("Temporal point permutation outside[0,23]")
        if stop_budget<0 or stop_budget>4 or segment_budget<0 or segment_budget>6:raise Error("Only bounded default or lower event caps supported")
        self._stop_budget=stop_budget;self._segment_budget=segment_budget
        self._order=point_order
        self.world=GpuCollisionWorld();self._closed=False;self.last_error=0
        self._candidate=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](WORDS);self._candidate.enqueue_fill(SENTINEL)
        self._summary=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](6);self._summary.enqueue_fill(0)
        self._stats=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](64);self._stats.enqueue_fill(SENTINEL)
        self._group=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](14);self._group.enqueue_fill(SENTINEL)
        self._episode=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](16);self._episode.enqueue_fill(UInt64.MAX)
        self._pending_episode=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](16);self._pending_episode.enqueue_fill(UInt64.MAX)
        self._last=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](48);self._last.enqueue_fill(SENTINEL)
        self._pending_last=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](48);self._pending_last.enqueue_fill(SENTINEL)
        self._block_input=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](64);self._block_input.enqueue_fill(SENTINEL)
        self._block_output=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](64);self._block_output.enqueue_fill(SENTINEL)
        with self._episode.map_to_host() as a:a[1]=0;a[2]=0

    def advance(mut self,dt: Float64=1.0/30,gravity: Vec3=Vec3(0,-9.81,0),restitution: Float64=0,coefficient: Float64=0) raises -> Int32:
        if self._closed:raise Error("Temporal floor owner closed")
        # Prior orphan/registry reconciliation stays an earlier transaction.
        _=self.world.submit_shapes(List[SphereCommand]())
        self.world.bodies._ctx.enqueue_function[unilateral_temporal_floor_friction](self.world.bodies._current,self._candidate,self.world.bodies._active,self.world.bodies._generations,self.world.bodies._namespace,self.world._meta,self.world._values,self._summary,self._stats,self._group,self._episode,self._pending_episode,self._last,self._pending_last,self._block_input,self._block_output,dt,gravity.x,gravity.y,gravity.z,restitution,coefficient,self._order,self._stop_budget,self._segment_budget,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.enqueue_function[commit_temporal](self.world.bodies._current,self._candidate,self._summary,self._episode,self._pending_episode,self._last,self._pending_last,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize()
        with self._summary.map_to_host() as a:self.last_error=Int32(a[0])
        return self.last_error

    def report(mut self) raises -> Array[Float64,62]:
        var result=Array[Float64,62](fill=0)
        with self._stats.map_to_host() as a:
            for i in range(62):result[i]=Float64(a[i+1])
        return result^
    def close(mut self) raises:
        if not self._closed:self.world.close();self._closed=True
