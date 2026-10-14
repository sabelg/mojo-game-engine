"""G02 persistent GPU body registry. Host packets are not a live-body registry.

Single-caller synchronous API: FIFO commands validate/apply on GPU scratch,
then commit together. Current state/active/generation buffers never map to host.
"""
from max.gpu.host import DeviceContext, DeviceBuffer
from std.collections import List, Array
from std.memory import Pointer
from std.ffi import external_call
from std.testing import assert_equal
from mojo_game.rigidbody3d import RigidBody3D
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion
from .core import BodyState
from .kernels import CAPACITY, STRIDE, FIELDS, WORDS, SENTINEL, STATUS_SENTINEL, reduce_status_kernel
from .lifecycle_kernels import CREATE, REMOVE, UPDATE, SET_FORCE, ALL_FORCE, META_SENTINEL
from .lifecycle_kernels import initialize_registry, copy_transaction, command_transaction, commit_transaction
from .lifecycle_kernels import integrate_live, commit_step, snapshot_registry, diagnostic_copy, generation_for_test, storage_stamp

from .lifecycle import BodyHandle,BodyCommand,BodyPose,body_state,empty_state,state_words,fresh_namespace
from .warm_cache_kernels import initialize_tracking,track_commands,track_integration
struct GpuWarmWorld(Movable):
    var _ctx: DeviceContext
    var _current: DeviceBuffer[DType.float64]
    var _scratch: DeviceBuffer[DType.float64]
    var _diagnostic: DeviceBuffer[DType.float64]
    var _active: DeviceBuffer[DType.int32]
    var _pending_active: DeviceBuffer[DType.int32]
    var _generations: DeviceBuffer[DType.uint64]
    var _pending_generations: DeviceBuffer[DType.uint64]
    var _namespace: DeviceBuffer[DType.uint64]
    var _statuses: DeviceBuffer[DType.int32]
    var _summary: DeviceBuffer[DType.int32]
    var _headers: DeviceBuffer[DType.uint64]
    var _payload: DeviceBuffer[DType.float64]
    var _results: DeviceBuffer[DType.uint64]
    var _metadata: DeviceBuffer[DType.uint64]
    var _poses: DeviceBuffer[DType.float64]
    var _addresses: DeviceBuffer[DType.uint64]
    var _closed: Bool
    var _command_capacity: Int
    var body_buffers_created: Int32
    var logical_command_bytes: Int64
    var last_error: Int32
    var last_bad_command: Int32
    var _warm_revisions: DeviceBuffer[DType.uint64]
    var _warm_state: DeviceBuffer[DType.uint64]
    var _warm_dt: DeviceBuffer[DType.float64]

    def __init__(out self) raises:
        self._ctx=DeviceContext()
        if String(self._ctx.name())!="NVIDIA GB10":raise Error("G02 GB10 profile only; no CPU fallback")
        self._current=self._ctx.enqueue_create_buffer[DType.float64](WORDS)
        self._scratch=self._ctx.enqueue_create_buffer[DType.float64](WORDS)
        self._diagnostic=self._ctx.enqueue_create_buffer[DType.float64](WORDS)
        self._active=self._ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._pending_active=self._ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._generations=self._ctx.enqueue_create_buffer[DType.uint64](STRIDE)
        self._pending_generations=self._ctx.enqueue_create_buffer[DType.uint64](STRIDE)
        self._namespace=self._ctx.enqueue_create_buffer[DType.uint64](3)
        self._statuses=self._ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._summary=self._ctx.enqueue_create_buffer[DType.int32](2)
        self._headers=self._ctx.enqueue_create_buffer[DType.uint64](2)
        self._payload=self._ctx.enqueue_create_buffer[DType.float64](2)
        self._results=self._ctx.enqueue_create_buffer[DType.uint64](2)
        self._metadata=self._ctx.enqueue_create_buffer[DType.uint64](CAPACITY*3+2)
        self._poses=self._ctx.enqueue_create_buffer[DType.float64](CAPACITY*7+2)
        self._addresses=self._ctx.enqueue_create_buffer[DType.uint64](2)
        self._closed=False;self._command_capacity=0;self.body_buffers_created=2
        self.logical_command_bytes=0;self.last_error=0;self.last_bad_command=-1
        self._current.enqueue_fill(SENTINEL);self._scratch.enqueue_fill(SENTINEL);self._diagnostic.enqueue_fill(SENTINEL)
        self._active.enqueue_fill(STATUS_SENTINEL);self._pending_active.enqueue_fill(STATUS_SENTINEL)
        self._generations.enqueue_fill(META_SENTINEL);self._pending_generations.enqueue_fill(META_SENTINEL)
        self._namespace.enqueue_fill(META_SENTINEL);self._statuses.enqueue_fill(STATUS_SENTINEL)
        self._summary.enqueue_fill(0);self._metadata.enqueue_fill(META_SENTINEL);self._poses.enqueue_fill(SENTINEL)
        with self._namespace.map_to_host() as values:values[1]=fresh_namespace()
        self._ctx.enqueue_function[initialize_registry](self._active,self._generations,grid_dim=4,block_dim=64)
        self._warm_revisions=self._ctx.enqueue_create_buffer[DType.uint64](CAPACITY+2);self._warm_revisions.enqueue_fill(UInt64.MAX)
        self._warm_state=self._ctx.enqueue_create_buffer[DType.uint64](9);self._warm_state.enqueue_fill(UInt64.MAX)
        self._warm_dt=self._ctx.enqueue_create_buffer[DType.float64](3);self._warm_dt.enqueue_fill(SENTINEL)
        self._ctx.enqueue_function[initialize_tracking](self._warm_revisions,self._warm_state,self._warm_dt,grid_dim=1,block_dim=1)
        self._ctx.synchronize()

    def _open(self) raises:
        if self._closed:raise Error("G02 world is closed")

    def device(self) raises -> String:
        self._open()
        return String(self._ctx.name())

    def submit(mut self,commands: List[BodyCommand]) raises -> List[BodyHandle]:
        self._open()
        var count=len(commands)
        if count>CAPACITY:raise Error("G02 command batch exceeds 256")
        var created=List[BodyHandle]()
        if count==0:return created^
        self._ctx.synchronize()
        if count!=self._command_capacity:
            # Staging can resize only after retirement; body buffers never resize.
            self._headers=self._ctx.enqueue_create_buffer[DType.uint64](count*4+2)
            self._payload=self._ctx.enqueue_create_buffer[DType.float64](count*FIELDS+2)
            self._results=self._ctx.enqueue_create_buffer[DType.uint64](count*3+2)
            self._command_capacity=count
        self._headers.enqueue_fill(META_SENTINEL);self._payload.enqueue_fill(SENTINEL);self._results.enqueue_fill(META_SENTINEL)
        with self._headers.map_to_host() as headers,self._payload.map_to_host() as values:
            for i in range(count):
                var command=commands[i];var h=1+i*4
                headers[h]=command.opcode;headers[h+1]=UInt64(command.handle.slot)
                headers[h+2]=command.handle.generation;headers[h+3]=command.handle.owner
                var words=state_words(command.data)
                for f in range(FIELDS):values[1+i*FIELDS+f]=words[f]
        self.logical_command_bytes+=Int64(count)*(4*8+FIELDS*8)
        self._ctx.enqueue_function[copy_transaction](self._current,self._scratch,self._active,self._pending_active,self._generations,self._pending_generations,grid_dim=4,block_dim=64)
        self._ctx.enqueue_function[command_transaction](self._scratch,self._pending_active,self._pending_generations,self._namespace,self._headers,self._payload,self._results,self._summary,Int32(count),grid_dim=1,block_dim=1)
        self._ctx.enqueue_function[commit_transaction](self._current,self._scratch,self._active,self._pending_active,self._generations,self._pending_generations,self._summary,grid_dim=4,block_dim=64)
        self._ctx.enqueue_function[track_commands](self._headers,self._summary,self._warm_revisions,self._warm_state,Int32(count),grid_dim=1,block_dim=1)
        self._ctx.synchronize()
        with self._summary.map_to_host() as result:
            self.last_error=Int32(result[0]);self.last_bad_command=Int32(result[1])
        if self.last_error:
            raise Error("GPU command transaction rejected; code="+String(self.last_error)+", index="+String(self.last_bad_command))
        var has_create=False
        for command in commands:
            if command.opcode==CREATE:has_create=True
        if has_create:
            with self._results.map_to_host() as results:
                assert_equal(results[0],META_SENTINEL);assert_equal(results[count*3+1],META_SENTINEL)
                for i in range(count):
                    if commands[i].opcode==CREATE:
                        created.append(BodyHandle(Int32(results[1+i*3]),UInt64(results[2+i*3]),UInt64(results[3+i*3])))
        return created^

    def step(mut self,dt: Float64,gravity: Vec3=Vec3(0,-9.81,0),ceiling: Float64=1.0/120) raises -> Int32:
        self._open()
        self._ctx.enqueue_function[integrate_live](self._current,self._scratch,self._active,self._statuses,dt,gravity.x,gravity.y,gravity.z,ceiling,grid_dim=4,block_dim=64)
        self._ctx.enqueue_function[reduce_status_kernel](self._statuses,self._summary,Int32(CAPACITY),grid_dim=1,block_dim=1)
        self._ctx.enqueue_function[commit_step](self._current,self._scratch,self._active,self._summary,grid_dim=4,block_dim=64)
        self._ctx.enqueue_function[track_integration](self._summary,self._warm_state,self._warm_dt,dt,grid_dim=1,block_dim=1)
        self._ctx.synchronize()
        with self._summary.map_to_host() as result:self.last_error=Int32(result[0])
        self.last_bad_command=-1
        return self.last_error

    def _snapshot(mut self) raises:
        self._open()
        self._ctx.enqueue_function[snapshot_registry](self._current,self._active,self._generations,self._namespace,self._metadata,self._poses,grid_dim=4,block_dim=64)
        self._ctx.synchronize()

    def poses(mut self) raises -> List[BodyPose]:
        self._snapshot()
        var result=List[BodyPose]()
        with self._metadata.map_to_host() as meta,self._poses.map_to_host() as poses:
            assert_equal(meta[0],META_SENTINEL);assert_equal(meta[CAPACITY*3+1],META_SENTINEL)
            assert_equal(poses[0],SENTINEL);assert_equal(poses[CAPACITY*7+1],SENTINEL)
            for i in range(CAPACITY):
                var m=1+i*3;var p=1+i*7
                if meta[m]==1:
                    result.append(BodyPose(BodyHandle(Int32(i),UInt64(meta[m+1]),UInt64(meta[m+2])),
                        Vec3(poses[p],poses[p+1],poses[p+2]),Quaternion(poses[p+3],poses[p+4],poses[p+5],poses[p+6])))
        return result^

    def raw(mut self) raises -> List[Float64]:
        self._open()
        # Diagnostic copy only: authoritative state never maps/writes on host.
        self._ctx.enqueue_function[diagnostic_copy](self._current,self._diagnostic,grid_dim=4,block_dim=64)
        self._ctx.synchronize()
        var result=List[Float64]()
        with self._diagnostic.map_to_host() as values:
            for i in range(WORDS):result.append(Float64(values[i]))
        return result^

    def metadata(mut self) raises -> List[UInt64]:
        self._snapshot()
        var result=List[UInt64]()
        with self._metadata.map_to_host() as values:
            for i in range(CAPACITY*3+2):result.append(UInt64(values[i]))
        return result^

    def test_generation(mut self,slot: Int32,generation: UInt64) raises:
        self._open()
        self._ctx.enqueue_function[generation_for_test](self._generations,slot,generation,grid_dim=1,block_dim=1)
        self._ctx.synchronize()

    def storage_ids(mut self) raises -> Tuple[UInt64,UInt64]:
        self._open()
        self._ctx.enqueue_function[storage_stamp](self._current,self._scratch,self._addresses,grid_dim=1,block_dim=1)
        self._ctx.synchronize()
        with self._addresses.map_to_host() as values:
            return UInt64(values[0]),UInt64(values[1])

    def close(mut self) raises:
        if self._closed:return
        self._ctx.synchronize()
        self._closed=True
        # Owned buffers/context reclaim at scope destruction; never free in flight.
