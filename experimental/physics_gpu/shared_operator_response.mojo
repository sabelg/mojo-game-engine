"""Separate opt-in32-lane point residual/Jacobian cooperation; serial modes retained."""
from max.gpu.host import DeviceBuffer
from std.collections import List
from .box_box import GpuBoxBoxDetection
from .kernels import WORDS,STRIDE,SENTINEL
from .shape_kernels import SHAPES,PAIRS,BOUNDS_FIELDS,POISON,prepare_bounds
from .box_box_kernels import box_pairs
from .box_response_kernels import begin_box_response,project_box_response,pack_box_response,solve_box_response,validate_box_response
from .cached_tangent_kernels import pack_coupled_tangent_metrics
from .shared_operator_kernels import solve_box_shared_operator
from std.math import isfinite
from std.collections import Array
from .response_kernels import commit_response
from .stability_kernels import copy_projected

from .box_response import BoxResponseReport

struct GpuSharedOperatorBoxResponse(Movable):
    var detection: GpuBoxBoxDetection
    var _debug: DeviceBuffer[DType.int64]
    var _parallel: Bool
    var _metrics: DeviceBuffer[DType.float64]
    var _work: DeviceBuffer[DType.int64]
    var _candidate: DeviceBuffer[DType.float64]
    var _projected: DeviceBuffer[DType.float64]
    var _private_bounds: DeviceBuffer[DType.float64]
    var _private_status: DeviceBuffer[DType.int32]
    var _initial: DeviceBuffer[DType.int32]
    var _position_impulses: DeviceBuffer[DType.float64]
    var _headers: DeviceBuffer[DType.uint64]
    var _geometry: DeviceBuffer[DType.float64]
    var _spans: DeviceBuffer[DType.int32]
    var _grams: DeviceBuffer[DType.float64]
    var _operators: DeviceBuffer[DType.float64]
    var _mask_valid: DeviceBuffer[DType.int32]
    var _impulses: DeviceBuffer[DType.float64]
    var _targets: DeviceBuffer[DType.float64]
    var _tangent: DeviceBuffer[DType.float64]
    var _touched: DeviceBuffer[DType.int32]
    var _summary: DeviceBuffer[DType.int32]
    var _stats: DeviceBuffer[DType.float64]
    var _residuals: DeviceBuffer[DType.float64]
    var _velocity_budget: Int32
    var _capacity: Int32
    var last_error: Int32
    var _closed: Bool

    def __init__(out self,capacity: Int32=64,velocity_budget: Int32=64,*,leader_only: Bool=False) raises:
        if capacity<0 or capacity>64:raise Error("Box response selected-point capacity must be in [0,64]")
        if velocity_budget!=64 and velocity_budget!=96:raise Error("Box response velocity policy must be explicitly 64 or 96")
        self._velocity_budget=velocity_budget
        self.detection=GpuBoxBoxDetection(pair_limit=2016,point_limit=18144,legacy_pair_limit=2016,legacy_contact_limit=2016);self._capacity=capacity;self.last_error=0;self._closed=False
        self._parallel=not leader_only
        self._debug=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int64](18);self._debug.enqueue_fill(0)
        self._work=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int64](16);self._work.enqueue_fill(0)
        self._metrics=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](1826);self._metrics.enqueue_fill(POISON)
        self._candidate=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](WORDS);self._candidate.enqueue_fill(SENTINEL)
        self._projected=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](WORDS);self._projected.enqueue_fill(SENTINEL)
        self._private_bounds=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](SHAPES*BOUNDS_FIELDS+2);self._private_bounds.enqueue_fill(POISON)
        self._private_status=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int32](SHAPES+2);self._private_status.enqueue_fill(-98765)
        self._initial=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2);self._initial.enqueue_fill(-98765)
        self._position_impulses=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](PAIRS+2);self._position_impulses.enqueue_fill(POISON)
        self._headers=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.uint64](64*11+2);self._headers.enqueue_fill(UInt64.MAX)
        self._geometry=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](64*10+2);self._geometry.enqueue_fill(POISON)
        self._spans=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int32](16*2+2);self._spans.enqueue_fill(-98765)
        self._grams=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](16*16+2);self._grams.enqueue_fill(POISON)
        self._operators=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](16*256+2);self._operators.enqueue_fill(POISON)
        self._mask_valid=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int32](16*16+2);self._mask_valid.enqueue_fill(-98765)
        self._impulses=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](66);self._impulses.enqueue_fill(POISON)
        self._targets=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](66);self._targets.enqueue_fill(POISON)
        self._tangent=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](130);self._tangent.enqueue_fill(POISON)
        self._touched=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int32](STRIDE);self._touched.enqueue_fill(-98765)
        self._residuals=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](96*2+2);self._residuals.enqueue_fill(POISON)
        self._summary=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.int32](6);self._stats=self.detection.world.bodies._ctx.enqueue_create_buffer[DType.float64](9)

    def resolve(mut self,dt: Float64,restitution: Float64=0,coefficient: Float64=0,velocity_iterations: Int32=32,position_iterations: Int32=32,*,basis_cos: Float64=1,basis_sin: Float64=0) raises -> BoxResponseReport:
        if self._closed:raise Error("Box response owner closed")
        if not isfinite(basis_cos) or not isfinite(basis_sin) or abs(basis_cos*basis_cos+basis_sin*basis_sin-1)>1e-12:
            self.last_error=111;raise Error("Coupled friction basis must be finite and orthonormal")
        self._work.enqueue_fill(0);self._debug.enqueue_fill(0)
        # Earlier registry/orphan reconciliation is the existing separate commit.
        try:_=self.detection.world._detect_on_device()
        except error:self.last_error=self.detection.world.last_error;raise error
        self.detection.world.bodies._ctx.enqueue_function[box_pairs](self.detection.world._meta,self.detection.world._bounds,self.detection.world._statuses,self.detection._flags,self.detection._counts,self.detection._errors,self.detection._features,self.detection._values,self.detection._points,grid_dim=64,block_dim=64)
        self.detection.world.bodies._ctx.enqueue_function[begin_box_response](self.detection.world.bodies._current,self._candidate,self.detection.world.bodies._active,self.detection.world._meta,self.detection.world._values,self.detection.world._statuses,self.detection._flags,self.detection._errors,self.detection._values,self._initial,self._position_impulses,self._summary,self._stats,dt,restitution,coefficient,velocity_iterations,position_iterations,self._velocity_budget,grid_dim=1,block_dim=1)
        self.detection.world.bodies._ctx.enqueue_function[project_box_response](self.detection.world.bodies._current,self._candidate,self.detection.world._meta,self._initial,self.detection._values,self._position_impulses,self._summary,self._stats,position_iterations,grid_dim=1,block_dim=1)
        self.detection.world.bodies._ctx.enqueue_function[prepare_bounds](self._candidate,self.detection.world._meta,self.detection.world._values,self._private_bounds,self._private_status,grid_dim=1,block_dim=64)
        self.detection.world.bodies._ctx.enqueue_function[box_pairs](self.detection.world._meta,self._private_bounds,self._private_status,self.detection._flags,self.detection._counts,self.detection._errors,self.detection._features,self.detection._values,self.detection._points,grid_dim=64,block_dim=64)
        self.detection.world.bodies._ctx.enqueue_function[pack_box_response](self._candidate,self.detection.world._meta,self._private_bounds,self._private_status,self._initial,self.detection._flags,self.detection._counts,self.detection._errors,self.detection._values,self.detection._points,self._headers,self._geometry,self._spans,self._grams,self._operators,self._mask_valid,self._impulses,self._targets,self._tangent,self._touched,self._summary,self._stats,self._capacity,restitution,grid_dim=1,block_dim=1)
        self.detection.world.bodies._ctx.enqueue_function[copy_projected](self._candidate,self._projected,self._summary,grid_dim=24,block_dim=256)
        if coefficient==0:
            self.detection.world.bodies._ctx.enqueue_function[solve_box_response](self._candidate,self._headers,self._geometry,self._spans,self._grams,self._operators,self._mask_valid,self._impulses,self._targets,self._tangent,self._touched,self._summary,self._stats,self._residuals,coefficient,velocity_iterations,grid_dim=1,block_dim=1)
        else:
            self.detection.world.bodies._ctx.enqueue_function[pack_coupled_tangent_metrics](self._candidate,self._headers,self._geometry,self._spans,self._summary,basis_cos,basis_sin,self._metrics,grid_dim=1,block_dim=1)
            self.detection.world.bodies._ctx.enqueue_function[solve_box_shared_operator](self._candidate,self._headers,self._geometry,self._spans,self._grams,self._operators,self._mask_valid,self._impulses,self._targets,self._tangent,self._touched,self._summary,self._stats,self._residuals,coefficient,velocity_iterations,basis_cos,basis_sin,self._work,self._metrics,self._debug,Int32(1 if self._parallel else 0),grid_dim=1,block_dim=32)
        self.detection.world.bodies._ctx.enqueue_function[validate_box_response](self._candidate,self._projected,self.detection.world._meta,self.detection._flags,self.detection._counts,self.detection._values,self.detection._points,self._summary,self._stats,restitution,grid_dim=1,block_dim=1)
        self.detection.world.bodies._ctx.enqueue_function[commit_response](self.detection.world.bodies._current,self._candidate,self.detection.world.bodies._active,self._summary,grid_dim=4,block_dim=64)
        self.detection.world.bodies._ctx.synchronize()
        with self._summary.map_to_host() as summary,self._stats.map_to_host() as stats:
            self.last_error=Int32(summary[0])
            if self.last_error:raise Error("GPU box response transaction rejected="+String(self.last_error))
            return BoxResponseReport(Int32(summary[3]),Int32(summary[4]),Int32(summary[5]),Int32(summary[1]),Int32(summary[2]),Float64(stats[0]),Float64(stats[1]),Float64(stats[2]),Float64(stats[7]),Float64(stats[3]),Float64(stats[4]),Float64(stats[8]))

    def work_report(mut self) raises -> Array[Int64,10]:
        var output=Array[Int64,10](fill=0)
        with self._work.map_to_host() as values:
            for i in range(10):output[i]=Int64(values[i])
        return output^

    def residual_history(mut self) raises -> List[Float64]:
        if self._closed:raise Error("Box response owner closed")
        var result=List[Float64]()
        with self._summary.map_to_host() as summary,self._residuals.map_to_host() as history:
            for i in range(Int(summary[1])):result.append(Float64(history[1+i*2]))
        return result^

    def close(mut self) raises:
        if self._closed:return
        self.detection.close();self._closed=True

    def cooperative_report(mut self) raises -> Array[Int64,18]:
        var result=Array[Int64,18](fill=0)
        with self._debug.map_to_host() as values:
            for i in range(18):result[i]=Int64(values[i])
        return result^
