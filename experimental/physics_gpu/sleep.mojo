"""G05b opt-in conservative GPU sleep state and whole-world idle gate."""
from max.gpu.host import DeviceContext,DeviceBuffer
from std.collections import List
from std.testing import assert_equal
from mojo_game import Vec3
from .recommended import GpuPhysicsResponse
from .collision import GpuCollisionWorld,SphereCommand,BoxCommand,ShapeHandle
from .lifecycle import BodyCommand,BodyHandle
from .kernels import CAPACITY,STRIDE,WORDS,SENTINEL
from .shape_kernels import PAIRS,META_FIELDS,SHAPE_STRIDE
from .island_kernels import MEMBER_WORDS,ISLAND_CONTACT_WORDS,construct_islands,initialize_islands,NO_ISLAND
from .sleep_kernels import *

@fieldwise_init
struct SleepStepReport(ImplicitlyCopyable,Movable):
    var epoch: UInt64
    var asleep: Int32
    var awake: Int32
    var entered_sleep: Int32
    var woke: Int32
    var integration_calls: Int32
    var response_calls: Int32
    var idle_skipped: Bool

@fieldwise_init
struct SleepMember(ImplicitlyCopyable,Movable):
    var body: BodyHandle
    var root: BodyHandle
    var asleep: Bool
    var dwell_seconds: Float64

struct SleepBuffers(Movable):
    var _members: DeviceBuffer[DType.uint64]
    var _pending_members: DeviceBuffer[DType.uint64]
    var _contacts: DeviceBuffer[DType.uint64]
    var _pending_contacts: DeviceBuffer[DType.uint64]
    var _parent: DeviceBuffer[DType.int32]
    var _seen: DeviceBuffer[DType.int32]
    var _graph_state: DeviceBuffer[DType.uint64]
    var _graph_summary: DeviceBuffer[DType.int32]
    var _state: DeviceBuffer[DType.uint64]
    var _pending: DeviceBuffer[DType.uint64]
    var _clock: DeviceBuffer[DType.float64]
    var _pending_clock: DeviceBuffer[DType.float64]
    var _observed: DeviceBuffer[DType.float64]
    var _anchor: DeviceBuffer[DType.float64]
    var _old_contacts: DeviceBuffer[DType.uint64]
    var _old_shapes: DeviceBuffer[DType.uint64]
    var _configuration: DeviceBuffer[DType.float64]
    var _publication: DeviceBuffer[DType.uint64]
    var _requests: DeviceBuffer[DType.int32]
    var _step_wake: DeviceBuffer[DType.int32]
    var _old_wake: DeviceBuffer[DType.int32]
    var _new_wake: DeviceBuffer[DType.int32]
    var _eligible: DeviceBuffer[DType.int32]
    var _supported: DeviceBuffer[DType.int32]
    var _sources: DeviceBuffer[DType.int32]
    var _old_map: DeviceBuffer[DType.int32]
    var _new_map: DeviceBuffer[DType.int32]
    var _summary: DeviceBuffer[DType.int32]
    var _wake_headers: DeviceBuffer[DType.uint64]
    var _capacity: Int32
    var last_error: Int32

    def __init__(out self,mut ctx: DeviceContext,capacity: Int32) raises:
        self._capacity=capacity;self.last_error=0
        self._members=ctx.enqueue_create_buffer[DType.uint64](CAPACITY*MEMBER_WORDS+2)
        self._members.enqueue_fill(UInt64.MAX)
        self._pending_members=ctx.enqueue_create_buffer[DType.uint64](CAPACITY*MEMBER_WORDS+2)
        self._pending_members.enqueue_fill(UInt64.MAX)
        self._contacts=ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*ISLAND_CONTACT_WORDS+2)
        self._contacts.enqueue_fill(UInt64.MAX)
        self._pending_contacts=ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*ISLAND_CONTACT_WORDS+2)
        self._pending_contacts.enqueue_fill(UInt64.MAX)
        self._parent=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._parent.enqueue_fill(-98765)
        self._seen=ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._seen.enqueue_fill(-98765)
        self._graph_state=ctx.enqueue_create_buffer[DType.uint64](6)
        self._graph_state.enqueue_fill(UInt64.MAX)
        self._graph_summary=ctx.enqueue_create_buffer[DType.int32](2)
        self._graph_summary.enqueue_fill(0)
        self._state=ctx.enqueue_create_buffer[DType.uint64](CAPACITY*SLEEP_WORDS+2)
        self._state.enqueue_fill(UInt64.MAX)
        self._pending=ctx.enqueue_create_buffer[DType.uint64](CAPACITY*SLEEP_WORDS+2)
        self._pending.enqueue_fill(UInt64.MAX)
        self._clock=ctx.enqueue_create_buffer[DType.float64](STRIDE*2)
        self._clock.enqueue_fill(SENTINEL)
        self._pending_clock=ctx.enqueue_create_buffer[DType.float64](STRIDE*2)
        self._pending_clock.enqueue_fill(SENTINEL)
        self._observed=ctx.enqueue_create_buffer[DType.float64](WORDS)
        self._observed.enqueue_fill(SENTINEL)
        self._anchor=ctx.enqueue_create_buffer[DType.float64](7*STRIDE)
        self._anchor.enqueue_fill(SENTINEL)
        self._old_contacts=ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*ISLAND_CONTACT_WORDS+2)
        self._old_contacts.enqueue_fill(UInt64.MAX)
        self._old_shapes=ctx.enqueue_create_buffer[DType.uint64](META_FIELDS*SHAPE_STRIDE)
        self._old_shapes.enqueue_fill(UInt64.MAX)
        self._configuration=ctx.enqueue_create_buffer[DType.float64](9)
        self._configuration.enqueue_fill(0)
        self._publication=ctx.enqueue_create_buffer[DType.uint64](8)
        self._publication.enqueue_fill(UInt64.MAX)
        self._requests=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._requests.enqueue_fill(0)
        self._step_wake=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._step_wake.enqueue_fill(0)
        self._old_wake=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._old_wake.enqueue_fill(0)
        self._new_wake=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._new_wake.enqueue_fill(0)
        self._eligible=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._eligible.enqueue_fill(0)
        self._supported=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._supported.enqueue_fill(0)
        self._sources=ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._sources.enqueue_fill(0)
        self._old_map=ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._old_map.enqueue_fill(-1)
        self._new_map=ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._new_map.enqueue_fill(-1)
        self._summary=ctx.enqueue_create_buffer[DType.int32](6)
        self._summary.enqueue_fill(0)
        self._wake_headers=ctx.enqueue_create_buffer[DType.uint64](CAPACITY*3+2)
        self._wake_headers.enqueue_fill(UInt64.MAX)
        ctx.enqueue_function[initialize_islands](self._graph_state,grid_dim=1,block_dim=1)
        ctx.enqueue_function[initialize_sleep](self._state,self._publication,grid_dim=1,block_dim=1)
        ctx.enqueue_function[zero_clocks](self._clock,self._pending_clock,grid_dim=4,block_dim=64)
        ctx.synchronize()

    def rebuild(mut self,mut world: GpuCollisionWorld) raises -> Int32:
        var counts=world._detect_on_device();var count=Int32(counts[1])
        world.bodies._ctx.enqueue_function[construct_islands](world.bodies._current,world.bodies._active,world.bodies._generations,world.bodies._namespace,
            world._meta,world._statuses,world._contact_flags,world._contact_out,
            self._parent,self._seen,self._pending_members,self._pending_contacts,self._members,self._contacts,self._graph_state,self._graph_summary,
            count,self._capacity,Int32(CAPACITY),grid_dim=1,block_dim=1)
        world.bodies._ctx.synchronize()
        with self._graph_summary.map_to_host() as status:self.last_error=Int32(status[0])
        if self.last_error:raise Error("GPU sleep island validation rejected="+String(self.last_error))
        return count

    def phase(mut self,mut world: GpuCollisionWorld,count: Int32,phase: Int32,dt: Float64,sleep_after: Float64,gravity: Vec3,e: Float64,mu: Float64,vi: Int32,pi: Int32,ceiling: Float64) raises -> Bool:
        world.bodies._ctx.enqueue_function[evaluate_sleep](world.bodies._current,self._members,self._contacts,world._contact_out,world._contact_values,world._meta,
            self._state,self._clock,self._observed,self._anchor,self._old_contacts,self._old_shapes,self._configuration,self._publication,
            self._pending,self._pending_clock,self._requests,self._step_wake,self._old_wake,self._new_wake,self._eligible,self._supported,self._sources,self._old_map,self._new_map,self._summary,
            count,self._capacity,phase,dt,sleep_after,gravity.x,gravity.y,gravity.z,e,mu,vi,pi,ceiling,grid_dim=1,block_dim=1)
        world.bodies._ctx.synchronize();var can_idle=False
        with self._summary.map_to_host() as result:self.last_error=Int32(result[0]);can_idle=result[1]!=0
        if self.last_error:raise Error("GPU sleep phase rejected="+String(self.last_error))
        return can_idle

    def commit(mut self,mut world: GpuCollisionWorld,count: Int32,gravity: Vec3,e: Float64,mu: Float64,vi: Int32,pi: Int32) raises:
        world.bodies._ctx.enqueue_function[commit_sleep](world.bodies._current,world._meta,self._contacts,
            self._pending,self._pending_clock,self._state,self._clock,self._observed,self._anchor,self._old_shapes,self._old_contacts,self._configuration,self._publication,self._requests,self._summary,
            count,self._capacity,gravity.x,gravity.y,gravity.z,e,mu,vi,pi,grid_dim=1,block_dim=1)
        world.bodies._ctx.synchronize()

struct GpuSleepingPhysics(Movable):
    var physics: GpuPhysicsResponse
    var sleep: SleepBuffers
    var _sleep_after: Float64
    var _idle_gate: Bool
    var _closed: Bool
    var last_integration_calls: Int32
    var last_response_calls: Int32

    def __init__(out self,capacity: Int32=64,sleep_after: Float64=.5,idle_gate: Bool=False) raises:
        if not isfinite(sleep_after) or sleep_after<0 or sleep_after>10:raise Error("Sleep dwell outside [0,10] seconds")
        self.physics=GpuPhysicsResponse(capacity)
        self.sleep=SleepBuffers(self.physics.response.normal.history.world.bodies._ctx,capacity)
        self._sleep_after=sleep_after;self._idle_gate=idle_gate;self._closed=False
        self.last_integration_calls=0;self.last_response_calls=0

    def _open(self) raises:
        if self._closed:raise Error("GPU sleep owner closed")
        self.physics.response.normal.history.world._open()

    def submit(mut self,commands: List[BodyCommand]) raises -> List[BodyHandle]:
        self._open();var created=self.physics.response.normal.history.world.bodies.submit(commands)
        if len(commands)>0:
            self.physics.response.normal.history.world.bodies._ctx.enqueue_function[mark_body_commands](self.physics.response.normal.history.world.bodies._headers,self.physics.response.normal.history.world.bodies._results,self.sleep._requests,Int32(len(commands)),grid_dim=1,block_dim=1)
            self.physics.response.normal.history.world.bodies._ctx.synchronize()
        return created^

    def submit_shapes(mut self,commands: List[SphereCommand]) raises -> List[ShapeHandle]:
        self._open();return self.physics.response.normal.history.world.submit_shapes(commands)
    def submit_boxes(mut self,commands: List[BoxCommand]) raises -> List[ShapeHandle]:
        self._open();return self.physics.response.normal.history.world.submit_boxes(commands)

    def wake(mut self,handles: List[BodyHandle]) raises:
        self._open()
        if len(handles)>CAPACITY:raise Error("Wake packet capacity 256")
        with self.sleep._wake_headers.map_to_host() as header:
            for i in range(len(handles)):
                header[1+i*3]=UInt64(handles[i].slot);header[2+i*3]=handles[i].generation;header[3+i*3]=handles[i].owner
        self.physics.response.normal.history.world.bodies._ctx.enqueue_function[wake_packet](self.sleep._wake_headers,self.physics.response.normal.history.world.bodies._active,self.physics.response.normal.history.world.bodies._generations,self.physics.response.normal.history.world.bodies._namespace,
            self.physics.response.normal.history.world.bodies._current,self.sleep._requests,self.sleep._summary,Int32(len(handles)),grid_dim=1,block_dim=1)
        self.physics.response.normal.history.world.bodies._ctx.synchronize()
        with self.sleep._summary.map_to_host() as result:self.sleep.last_error=Int32(result[0])
        if self.sleep.last_error:raise Error("GPU wake packet rejected="+String(self.sleep.last_error))

    def step(mut self,dt: Float64,gravity: Vec3=Vec3(0,-9.81,0),restitution: Float64=0,coefficient: Float64=0,velocity_iterations: Int32=32,position_iterations: Int32=32,ceiling: Float64=1.0/120) raises -> SleepStepReport:
        self._open();self.last_integration_calls=0;self.last_response_calls=0
        var count=self.sleep.rebuild(self.physics.response.normal.history.world)
        var can_idle=self.sleep.phase(self.physics.response.normal.history.world,count,0,dt,self._sleep_after,gravity,restitution,coefficient,velocity_iterations,position_iterations,ceiling)
        var skipped=self._idle_gate and can_idle
        if not skipped:
            self.last_integration_calls=1
            var error=self.physics.response.normal.history.world.bodies.step(dt,gravity,ceiling)
            if error!=0:raise Error("GPU sleep integration failed="+String(error))
            self.last_response_calls=1
            _=self.physics.resolve(dt,restitution,coefficient,velocity_iterations,position_iterations)
        count=self.sleep.rebuild(self.physics.response.normal.history.world)
        _=self.sleep.phase(self.physics.response.normal.history.world,count,1,dt,self._sleep_after,gravity,restitution,coefficient,velocity_iterations,position_iterations,ceiling)
        self.sleep.commit(self.physics.response.normal.history.world,count,gravity,restitution,coefficient,velocity_iterations,position_iterations)
        with self.sleep._publication.map_to_host() as state,self.sleep._summary.map_to_host() as summary:
            assert_equal(state[0],UInt64.MAX);assert_equal(state[7],UInt64.MAX)
            return SleepStepReport(UInt64(state[1]),Int32(state[3]),Int32(state[4]),Int32(summary[4]),Int32(summary[5]),self.last_integration_calls,self.last_response_calls,skipped)

    def snapshot(mut self) raises -> List[SleepMember]:
        self._open();var result=List[SleepMember]()
        with self.sleep._state.map_to_host() as state,self.sleep._clock.map_to_host() as clock:
            assert_equal(state[0],UInt64.MAX);assert_equal(state[CAPACITY*SLEEP_WORDS+1],UInt64.MAX)
            for i in range(CAPACITY):
                var s=1+i*SLEEP_WORDS
                if state[s]!=1 or state[s+2]!=1:continue
                var owner=UInt64(state[s+6]);var root=UInt64(state[s+3])
                result.append(SleepMember(BodyHandle(Int32(i),UInt64(state[s+1]),owner),BodyHandle(Int32(root),UInt64(state[s+4]),owner),state[s+5]!=0,Float64(clock[i+1])))
        return result^

    def close(mut self) raises:
        if self._closed:return
        self.physics.close();self._closed=True
