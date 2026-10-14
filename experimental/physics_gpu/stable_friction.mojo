"""G04 stability: private projection before fresh cold contact-velocity solve."""
from max.gpu.host import DeviceBuffer
from .friction_response import GpuFrictionResponse,FrictionReport
from .normal_response import ResponseReport
from .kernels import WORDS,SENTINEL
from .response_kernels import setup_response,solve_velocities,project_positions,validate_response,commit_response
from .shape_kernels import prepare_bounds,pair_geometry,compact_detection,PAIRS
from .friction_kernels import prepare_friction,solve_friction
from .stability_kernels import validate_projected,copy_projected

@fieldwise_init
struct StableReport(ImplicitlyCopyable,Movable):
    var friction: FrictionReport
    var initial_contacts: Int32
    var projected_contacts: Int32

struct GpuStableFrictionResponse(Movable):
    var response: GpuFrictionResponse
    var _projected: DeviceBuffer[DType.float64]
    def __init__(out self,capacity: Int32=64,basis_angle: Float64=0) raises:
        self.response=GpuFrictionResponse(capacity,basis_angle)
        self._projected=self.response.normal.history.world.bodies._ctx.enqueue_create_buffer[DType.float64](WORDS)
        self._projected.enqueue_fill(SENTINEL)
    def resolve(mut self,dt: Float64,restitution: Float64=0,coefficient: Float64=0,velocity_iterations: Int32=32,position_iterations: Int32=32) raises -> StableReport:
        if self.response.normal._closed:raise Error("GPU stability owner closed")
        var counts: Tuple[Int,Int]
        try:counts=self.response.normal.history.world._detect_on_device()
        except error:
            self.response.normal.last_error=self.response.normal.history.world.last_error
            raise error
        return self._solve_prepared(Int32(counts[1]),dt,restitution,velocity_iterations,position_iterations,coefficient)
    def _solve_prepared(mut self,count: Int32,dt: Float64,e: Float64,vi: Int32=32,pi: Int32=32,mu: Float64=0) raises -> StableReport:
        # Internal qualification boundary only. Exact regenerated bounds and full
        # key checks reject stale prepared poses/revisions/generations.
        self.response.normal.history.world._open()
        self.response.normal.history.world.bodies._ctx.enqueue_function[prepare_bounds](self.response.normal.history.world.bodies._current,self.response.normal.history.world._meta,self.response.normal.history.world._values,self.response.normal._bounds,self.response.normal._statuses,grid_dim=1,block_dim=64)
        self.response.normal.history.world.bodies._ctx.enqueue_function[setup_response](self.response.normal.history.world.bodies._current,self.response.normal._candidate,self.response.normal.history.world.bodies._active,self.response.normal.history.world.bodies._generations,self.response.normal.history.world.bodies._namespace,
            self.response.normal.history.world._meta,self.response.normal.history.world._values,self.response.normal.history.world._bounds,self.response.normal._bounds,self.response.normal._statuses,self.response.normal.history.world._contact_out,self.response.normal.history.world._contact_values,self.response.normal.history.world._geometry,
            self.response.normal._impulses,self.response.normal._position_impulses,self.response.normal._targets,self.response.normal._effective,self.response.normal._touched,self.response.normal._summary,self.response.normal._stats,count,self.response.normal._capacity,dt,e,vi,pi,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[prepare_friction](self.response.normal._candidate,self.response.normal.history.world._contact_out,self.response.normal.history.world._contact_values,self.response._tangent,self.response.normal._summary,self.response._friction_stats,count,self.response.normal._capacity,mu,self.response._cos,self.response._sin,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[project_positions](self.response.normal.history.world.bodies._current,self.response.normal._candidate,self.response.normal.history.world._contact_out,self.response.normal.history.world._contact_values,self.response.normal._position_impulses,self.response.normal._effective,self.response.normal._summary,self.response.normal._stats,count,pi,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[prepare_bounds](self.response.normal._candidate,self.response.normal.history.world._meta,self.response.normal.history.world._values,self.response.normal._bounds,self.response.normal._statuses,grid_dim=1,block_dim=64)
        self.response.normal.history.world.bodies._ctx.enqueue_function[pair_geometry](self.response.normal.history.world._meta,self.response.normal._bounds,self.response.normal._statuses,self.response.normal._candidate_flags,self.response.normal._contact_flags,self.response.normal._geometry,grid_dim=64,block_dim=64)
        self.response.normal.history.world.bodies._ctx.enqueue_function[compact_detection](self.response.normal.history.world._meta,self.response.normal._statuses,self.response.normal._candidate_flags,self.response.normal._contact_flags,self.response.normal._geometry,self.response.normal._pair_out,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._post_summary,Int32(PAIRS),self.response.normal._capacity,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[validate_projected](self.response.normal.history.world._contact_out,count,self.response.normal._candidate,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._post_summary,self.response.normal._summary,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[copy_projected](self.response.normal._candidate,self._projected,self.response.normal._summary,grid_dim=24,block_dim=256)
        self.response.normal.history.world.bodies._ctx.synchronize()
        var initial_count=count;var projected_count=Int32(0);var position_used=Int32(0);var maximum_shift=Float64(0)
        with self.response.normal._summary.map_to_host() as result,self.response.normal._stats.map_to_host() as stats,self.response.normal._post_summary.map_to_host() as post:
            self.response.normal.last_error=Int32(result[0])
            if self.response.normal.last_error:raise Error("GPU stability projection rejected; code="+String(self.response.normal.last_error))
            position_used=Int32(result[2]);maximum_shift=Float64(stats[4]);projected_count=Int32(post[2])
        # New incoming velocity constraints use the privately projected pose.
        self.response.normal.history.world.bodies._ctx.enqueue_function[prepare_bounds](self._projected,self.response.normal.history.world._meta,self.response.normal.history.world._values,self.response.normal.history.world._bounds,self.response.normal._statuses,grid_dim=1,block_dim=64)
        self.response.normal.history.world.bodies._ctx.enqueue_function[setup_response](self._projected,self.response.normal._candidate,self.response.normal.history.world.bodies._active,self.response.normal.history.world.bodies._generations,self.response.normal.history.world.bodies._namespace,
            self.response.normal.history.world._meta,self.response.normal.history.world._values,self.response.normal._bounds,self.response.normal.history.world._bounds,self.response.normal._statuses,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._geometry,
            self.response.normal._impulses,self.response.normal._position_impulses,self.response.normal._targets,self.response.normal._effective,self.response.normal._touched,self.response.normal._summary,self.response.normal._stats,projected_count,self.response.normal._capacity,dt,e,vi,pi,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[prepare_friction](self.response.normal._candidate,self.response.normal._contact_out,self.response.normal._contact_values,self.response._tangent,self.response.normal._summary,self.response._friction_stats,projected_count,self.response.normal._capacity,mu,self.response._cos,self.response._sin,grid_dim=1,block_dim=1)
        if mu==0:
            self.response.normal.history.world.bodies._ctx.enqueue_function[solve_velocities](self.response.normal._candidate,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._impulses,self.response.normal._targets,self.response.normal._effective,self.response.normal._touched,self.response.normal._summary,self.response.normal._stats,projected_count,vi,grid_dim=1,block_dim=1)
        else:
            self.response.normal.history.world.bodies._ctx.enqueue_function[solve_friction](self.response.normal._candidate,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._impulses,self.response.normal._targets,self.response.normal._effective,self.response.normal._touched,self.response.normal._summary,self.response.normal._stats,self.response._tangent,self.response._friction_stats,projected_count,vi,mu,self.response._cos,self.response._sin,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[prepare_bounds](self.response.normal._candidate,self.response.normal.history.world._meta,self.response.normal.history.world._values,self.response.normal._bounds,self.response.normal._statuses,grid_dim=1,block_dim=64)
        self.response.normal.history.world.bodies._ctx.enqueue_function[pair_geometry](self.response.normal.history.world._meta,self.response.normal._bounds,self.response.normal._statuses,self.response.normal._candidate_flags,self.response.normal._contact_flags,self.response.normal._geometry,grid_dim=64,block_dim=64)
        self.response.normal.history.world.bodies._ctx.enqueue_function[compact_detection](self.response.normal.history.world._meta,self.response.normal._statuses,self.response.normal._candidate_flags,self.response.normal._contact_flags,self.response.normal._geometry,self.response.normal._pair_out,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._post_summary,Int32(PAIRS),self.response.normal._capacity,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[validate_response](self.response.normal._candidate,self.response.normal._contact_out,self.response.normal._contact_values,self.response.normal._post_summary,self.response.normal._summary,self.response.normal._stats,grid_dim=1,block_dim=1)
        self.response.normal.history.world.bodies._ctx.enqueue_function[commit_response](self.response.normal.history.world.bodies._current,self.response.normal._candidate,self.response.normal.history.world.bodies._active,self.response.normal._summary,grid_dim=4,block_dim=64)
        self.response.normal.history.world.bodies._ctx.synchronize()
        with self.response.normal._summary.map_to_host() as result,self.response.normal._stats.map_to_host() as stats,self.response._friction_stats.map_to_host() as friction:
            self.response.normal.last_error=Int32(result[0])
            if self.response.normal.last_error:raise Error("GPU normal-response transaction rejected; code="+String(self.response.normal.last_error))
            return StableReport(FrictionReport(ResponseReport(Int32(result[3]),Int32(result[4]),Int32(result[1]),position_used,Float64(stats[0]),Float64(stats[1]),Float64(stats[2]),Float64(stats[3]),maximum_shift),mu,Float64(friction[0]),Float64(friction[1]),Float64(friction[2]),Int32(friction[3])),initial_count,projected_count)

    def close(mut self) raises:
        self.response.close()
