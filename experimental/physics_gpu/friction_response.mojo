"""G04b one-coefficient cold Coulomb friction over unchanged G04a machinery."""
from max.gpu.host import DeviceBuffer
from std.collections import List
from std.math import cos,sin
from .normal_response import GpuNormalResponse,ResponseReport
from .response_kernels import setup_response,solve_velocities,project_positions,validate_response,commit_response
from .shape_kernels import prepare_bounds,pair_geometry,compact_detection,PAIRS
from .friction_kernels import prepare_friction,solve_friction

@fieldwise_init
struct FrictionReport(ImplicitlyCopyable,Movable):
    var normal: ResponseReport
    var coefficient: Float64
    var tangent_residual: Float64
    var maximum_tangent_impulse: Float64
    var cone_excess: Float64
    var sliding_contacts: Int32

struct GpuFrictionResponse(Movable):
    var normal: GpuNormalResponse
    var _tangent: DeviceBuffer[DType.float64]
    var _friction_stats: DeviceBuffer[DType.float64]
    var _cos: Float64
    var _sin: Float64
    def __init__(out self,capacity: Int32=64,basis_angle: Float64=0) raises:
        self.normal=GpuNormalResponse(capacity)
        self._tangent=self.normal.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)*2+2)
        self._friction_stats=self.normal.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](5)
        self._cos=cos(basis_angle);self._sin=sin(basis_angle)
    def resolve(mut self,dt: Float64,restitution: Float64=0,coefficient: Float64=0,velocity_iterations: Int32=32,position_iterations: Int32=32) raises -> FrictionReport:
        if self.normal._closed:raise Error("G04b response closed")
        var counts: Tuple[Int,Int]
        try:counts=self.normal.history.world._detect_on_device()
        except error:
            self.normal.last_error=self.normal.history.world.last_error
            raise error
        return self._solve_prepared(Int32(counts[1]),dt,restitution,velocity_iterations,position_iterations,coefficient)
    def _solve_prepared(mut self,count: Int32,dt: Float64,e: Float64,vi: Int32=32,pi: Int32=32,mu: Float64=0) raises -> FrictionReport:
        # Internal qualification boundary only. Exact regenerated bounds and full
        # key checks reject stale prepared poses/revisions/generations.
        self.normal.history.world._open()
        self.normal.history.world.bodies._ctx.enqueue_function[prepare_bounds](self.normal.history.world.bodies._current,self.normal.history.world._meta,self.normal.history.world._values,self.normal._bounds,self.normal._statuses,grid_dim=1,block_dim=64)
        self.normal.history.world.bodies._ctx.enqueue_function[setup_response](self.normal.history.world.bodies._current,self.normal._candidate,self.normal.history.world.bodies._active,self.normal.history.world.bodies._generations,self.normal.history.world.bodies._namespace,
            self.normal.history.world._meta,self.normal.history.world._values,self.normal.history.world._bounds,self.normal._bounds,self.normal._statuses,self.normal.history.world._contact_out,self.normal.history.world._contact_values,self.normal.history.world._geometry,
            self.normal._impulses,self.normal._position_impulses,self.normal._targets,self.normal._effective,self.normal._touched,self.normal._summary,self.normal._stats,count,self.normal._capacity,dt,e,vi,pi,grid_dim=1,block_dim=1)
        self.normal.history.world.bodies._ctx.enqueue_function[prepare_friction](self.normal._candidate,self.normal.history.world._contact_out,self.normal.history.world._contact_values,self._tangent,self.normal._summary,self._friction_stats,count,self.normal._capacity,mu,self._cos,self._sin,grid_dim=1,block_dim=1)
        if mu==0:
            self.normal.history.world.bodies._ctx.enqueue_function[solve_velocities](self.normal._candidate,self.normal.history.world._contact_out,self.normal.history.world._contact_values,self.normal._impulses,self.normal._targets,self.normal._effective,self.normal._touched,self.normal._summary,self.normal._stats,count,vi,grid_dim=1,block_dim=1)
        else:
            self.normal.history.world.bodies._ctx.enqueue_function[solve_friction](self.normal._candidate,self.normal.history.world._contact_out,self.normal.history.world._contact_values,self.normal._impulses,self.normal._targets,self.normal._effective,self.normal._touched,self.normal._summary,self.normal._stats,self._tangent,self._friction_stats,count,vi,mu,self._cos,self._sin,grid_dim=1,block_dim=1)
        self.normal.history.world.bodies._ctx.enqueue_function[project_positions](self.normal.history.world.bodies._current,self.normal._candidate,self.normal.history.world._contact_out,self.normal.history.world._contact_values,self.normal._position_impulses,self.normal._effective,self.normal._summary,self.normal._stats,count,pi,grid_dim=1,block_dim=1)
        self.normal.history.world.bodies._ctx.enqueue_function[prepare_bounds](self.normal._candidate,self.normal.history.world._meta,self.normal.history.world._values,self.normal._bounds,self.normal._statuses,grid_dim=1,block_dim=64)
        self.normal.history.world.bodies._ctx.enqueue_function[pair_geometry](self.normal.history.world._meta,self.normal._bounds,self.normal._statuses,self.normal._candidate_flags,self.normal._contact_flags,self.normal._geometry,grid_dim=64,block_dim=64)
        self.normal.history.world.bodies._ctx.enqueue_function[compact_detection](self.normal.history.world._meta,self.normal._statuses,self.normal._candidate_flags,self.normal._contact_flags,self.normal._geometry,self.normal._pair_out,self.normal._contact_out,self.normal._contact_values,self.normal._post_summary,Int32(PAIRS),self.normal._capacity,grid_dim=1,block_dim=1)
        self.normal.history.world.bodies._ctx.enqueue_function[validate_response](self.normal._candidate,self.normal._contact_out,self.normal._contact_values,self.normal._post_summary,self.normal._summary,self.normal._stats,grid_dim=1,block_dim=1)
        self.normal.history.world.bodies._ctx.enqueue_function[commit_response](self.normal.history.world.bodies._current,self.normal._candidate,self.normal.history.world.bodies._active,self.normal._summary,grid_dim=4,block_dim=64)
        self.normal.history.world.bodies._ctx.synchronize()
        with self.normal._summary.map_to_host() as result,self.normal._stats.map_to_host() as stats,self._friction_stats.map_to_host() as friction:
            self.normal.last_error=Int32(result[0])
            if self.normal.last_error:raise Error("GPU normal-response transaction rejected; code="+String(self.normal.last_error))
            return FrictionReport(ResponseReport(Int32(result[3]),Int32(result[4]),Int32(result[1]),Int32(result[2]),Float64(stats[0]),Float64(stats[1]),Float64(stats[2]),Float64(stats[3]),Float64(stats[4])),mu,Float64(friction[0]),Float64(friction[1]),Float64(friction[2]),Int32(friction[3]))

    def tangents(mut self) raises -> List[Float64]:
        if self.normal._closed:raise Error("G04b response closed")
        var result=List[Float64]()
        with self._tangent.map_to_host() as data:
            for i in range(Int(self.normal._capacity)*2+2):result.append(Float64(data[i]))
        return result^
    def close(mut self) raises:
        self.normal.close()
