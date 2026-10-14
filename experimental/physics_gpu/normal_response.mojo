"""G04a correctness profile: serial GPU normal response with atomic body commit."""
from max.gpu.host import DeviceBuffer
from std.collections import List
from .contact_history import GpuContactHistory
from .kernels import WORDS,SENTINEL,STRIDE
from .shape_kernels import SHAPES,PAIRS,BOUNDS_FIELDS,CONTACT_FIELDS,PAIR_HEADER,POISON,prepare_bounds,pair_geometry,compact_detection
from .response_kernels import setup_response,solve_velocities,project_positions,validate_response,commit_response

@fieldwise_init
struct ResponseReport(ImplicitlyCopyable,Movable):
    var contacts: Int32
    var fixed_pairs: Int32
    var velocity_iterations: Int32
    var position_iterations: Int32
    var energy_before: Float64
    var energy_after: Float64
    var velocity_residual: Float64
    var penetration: Float64
    var projection_shift: Float64

struct GpuNormalResponse(Movable):
    var history: GpuContactHistory
    var _candidate: DeviceBuffer[DType.float64]
    var _impulses: DeviceBuffer[DType.float64]
    var _position_impulses: DeviceBuffer[DType.float64]
    var _targets: DeviceBuffer[DType.float64]
    var _effective: DeviceBuffer[DType.float64]
    var _touched: DeviceBuffer[DType.int32]
    var _bounds: DeviceBuffer[DType.float64]
    var _statuses: DeviceBuffer[DType.int32]
    var _candidate_flags: DeviceBuffer[DType.int32]
    var _contact_flags: DeviceBuffer[DType.int32]
    var _geometry: DeviceBuffer[DType.float64]
    var _pair_out: DeviceBuffer[DType.uint64]
    var _contact_out: DeviceBuffer[DType.uint64]
    var _contact_values: DeviceBuffer[DType.float64]
    var _post_summary: DeviceBuffer[DType.int32]
    var _summary: DeviceBuffer[DType.int32]
    var _stats: DeviceBuffer[DType.float64]
    var _capacity: Int32
    var last_error: Int32
    var _closed: Bool

    def __init__(out self,capacity: Int32=64) raises:
        if capacity<0 or capacity>64:raise Error("G04a response contact capacity must be in [0,64]")
        self.history=GpuContactHistory(2016,2016);self._capacity=capacity;self.last_error=0;self._closed=False
        self._candidate=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](WORDS)
        self._impulses=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)+2)
        self._position_impulses=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)+2)
        self._targets=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)+2)
        self._effective=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)+2)
        self._touched=self.history.world.bodies._ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._bounds=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](SHAPES*BOUNDS_FIELDS+2)
        self._statuses=self.history.world.bodies._ctx.enqueue_create_buffer[DType.int32](SHAPES+2)
        self._candidate_flags=self.history.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._contact_flags=self.history.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._geometry=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](PAIRS*CONTACT_FIELDS+2)
        self._pair_out=self.history.world.bodies._ctx.enqueue_create_buffer[DType.uint64](PAIRS*PAIR_HEADER+2)
        self._contact_out=self.history.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*PAIR_HEADER+2)
        self._contact_values=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)*CONTACT_FIELDS+2)
        self._post_summary=self.history.world.bodies._ctx.enqueue_create_buffer[DType.int32](4)
        self._summary=self.history.world.bodies._ctx.enqueue_create_buffer[DType.int32](5)
        self._stats=self.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](6)
        self._candidate.enqueue_fill(SENTINEL);self._bounds.enqueue_fill(POISON);self._geometry.enqueue_fill(POISON);self._contact_values.enqueue_fill(POISON)
        self._impulses.enqueue_fill(POISON);self._position_impulses.enqueue_fill(POISON);self._targets.enqueue_fill(POISON);self._effective.enqueue_fill(POISON)
        self._pair_out.enqueue_fill(UInt64.MAX);self._contact_out.enqueue_fill(UInt64.MAX)

    def resolve(mut self,dt: Float64,restitution: Float64=0,velocity_iterations: Int32=32,position_iterations: Int32=32) raises -> ResponseReport:
        if self._closed:raise Error("G04a response closed")
        var counts: Tuple[Int,Int]
        try:counts=self.history.world._detect_on_device()
        except error:
            self.last_error=self.history.world.last_error
            raise error
        return self._solve_prepared(Int32(counts[1]),dt,restitution,velocity_iterations,position_iterations)

    def _solve_prepared(mut self,count: Int32,dt: Float64,e: Float64,vi: Int32=32,pi: Int32=32) raises -> ResponseReport:
        # Internal qualification boundary only. Exact regenerated bounds and full
        # key checks reject stale prepared poses/revisions/generations.
        self.history.world._open()
        self.history.world.bodies._ctx.enqueue_function[prepare_bounds](self.history.world.bodies._current,self.history.world._meta,self.history.world._values,self._bounds,self._statuses,grid_dim=1,block_dim=64)
        self.history.world.bodies._ctx.enqueue_function[setup_response](self.history.world.bodies._current,self._candidate,self.history.world.bodies._active,self.history.world.bodies._generations,self.history.world.bodies._namespace,
            self.history.world._meta,self.history.world._values,self.history.world._bounds,self._bounds,self._statuses,self.history.world._contact_out,self.history.world._contact_values,self.history.world._geometry,
            self._impulses,self._position_impulses,self._targets,self._effective,self._touched,self._summary,self._stats,count,self._capacity,dt,e,vi,pi,grid_dim=1,block_dim=1)
        self.history.world.bodies._ctx.enqueue_function[solve_velocities](self._candidate,self.history.world._contact_out,self.history.world._contact_values,self._impulses,self._targets,self._effective,self._touched,self._summary,self._stats,count,vi,grid_dim=1,block_dim=1)
        self.history.world.bodies._ctx.enqueue_function[project_positions](self.history.world.bodies._current,self._candidate,self.history.world._contact_out,self.history.world._contact_values,self._position_impulses,self._effective,self._summary,self._stats,count,pi,grid_dim=1,block_dim=1)
        self.history.world.bodies._ctx.enqueue_function[prepare_bounds](self._candidate,self.history.world._meta,self.history.world._values,self._bounds,self._statuses,grid_dim=1,block_dim=64)
        self.history.world.bodies._ctx.enqueue_function[pair_geometry](self.history.world._meta,self._bounds,self._statuses,self._candidate_flags,self._contact_flags,self._geometry,grid_dim=64,block_dim=64)
        self.history.world.bodies._ctx.enqueue_function[compact_detection](self.history.world._meta,self._statuses,self._candidate_flags,self._contact_flags,self._geometry,self._pair_out,self._contact_out,self._contact_values,self._post_summary,Int32(PAIRS),self._capacity,grid_dim=1,block_dim=1)
        self.history.world.bodies._ctx.enqueue_function[validate_response](self._candidate,self._contact_out,self._contact_values,self._post_summary,self._summary,self._stats,grid_dim=1,block_dim=1)
        self.history.world.bodies._ctx.enqueue_function[commit_response](self.history.world.bodies._current,self._candidate,self.history.world.bodies._active,self._summary,grid_dim=4,block_dim=64)
        self.history.world.bodies._ctx.synchronize()
        with self._summary.map_to_host() as result,self._stats.map_to_host() as stats:
            self.last_error=Int32(result[0])
            if self.last_error:raise Error("GPU normal-response transaction rejected; code="+String(self.last_error))
            return ResponseReport(Int32(result[3]),Int32(result[4]),Int32(result[1]),Int32(result[2]),Float64(stats[0]),Float64(stats[1]),Float64(stats[2]),Float64(stats[3]),Float64(stats[4]))

    def impulses(mut self) raises -> List[Float64]:
        # Diagnostic output only; never an input to subsequent resolves.
        if self._closed:raise Error("G04a response closed")
        var values=List[Float64]()
        with self._impulses.map_to_host() as data:
            for i in range(Int(self._capacity)+2):values.append(Float64(data[i]))
        return values^

    def close(mut self) raises:
        if self._closed:return
        self.history.close();self._closed=True
