"""Separate detection-only box/box patches; original one-point APIs unchanged."""
from max.gpu.host import DeviceBuffer
from std.collections import List
from std.memory import Pointer

def float_bits(value: Float64) -> UInt64:
    # Diagnostic-only equal-size scalar read, lifetime remains within this call.
    var stored=value
    return Pointer[UInt64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=stored)))[]

from std.testing import assert_equal
from mojo_game import Vec3
from .collision import GpuCollisionWorld,PairKey,ShapeHandle,DetectionFrame
from .lifecycle import BodyHandle
from .shape_kernels import PAIRS,POISON
from .box_box_kernels import *

@fieldwise_init
struct BoxContactPoint(ImplicitlyCopyable,Movable):
    var witness_a_relative: Vec3
    var witness_b_relative: Vec3
    var separation: Float64
    def depth(self) -> Float64:
        return max(0.0,-self.separation)

@fieldwise_init
struct BoxContactPatch(Movable):
    var key: PairKey
    var origin: Vec3
    var normal: Vec3
    var separation: Float64
    var feature: Int32
    var ambiguous: Bool
    var coalesced: Bool
    var points: List[BoxContactPoint]
    def depth(self) -> Float64:
        return max(0.0,-self.separation)

@fieldwise_init
struct BoxBoxFrame(Movable):
    var epoch: UInt64
    var patches: List[BoxContactPatch]
    var legacy: DetectionFrame

struct GpuBoxBoxDetection(Movable):
    var world: GpuCollisionWorld
    var _flags: DeviceBuffer[DType.int32]
    var _counts: DeviceBuffer[DType.int32]
    var _errors: DeviceBuffer[DType.int32]
    var _features: DeviceBuffer[DType.uint64]
    var _values: DeviceBuffer[DType.float64]
    var _points: DeviceBuffer[DType.float64]
    var _headers: DeviceBuffer[DType.uint64]
    var _output: DeviceBuffer[DType.float64]
    var _point_output: DeviceBuffer[DType.float64]
    var _state: DeviceBuffer[DType.uint64]
    var _summary: DeviceBuffer[DType.int32]
    var _pair_limit: Int32
    var _point_limit: Int32
    var _closed: Bool
    var last_error: Int32

    def __init__(out self,pair_limit: Int32=256,point_limit: Int32=1024,legacy_pair_limit: Int32=256,legacy_contact_limit: Int32=256) raises:
        if pair_limit<0 or pair_limit>Int32(PAIRS) or point_limit<0 or point_limit>Int32(PAIRS*PATCH_POINTS):raise Error("Box/box output capacity outside admitted range")
        self.world=GpuCollisionWorld(legacy_pair_limit,legacy_contact_limit);self._pair_limit=pair_limit;self._point_limit=point_limit;self._closed=False;self.last_error=0
        self._flags=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._counts=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._errors=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._features=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](PAIRS*2+2)
        self._values=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](PAIRS*7+2)
        self._points=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](PAIRS*PATCH_POINTS*PATCH_FIELDS+2)
        self._headers=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(pair_limit)*BB_HEADER+2)
        self._output=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(pair_limit)*7+2)
        self._point_output=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(point_limit)*PATCH_FIELDS+2)
        self._state=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](5)
        self._summary=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](1)
        self._flags.enqueue_fill(-98765);self._counts.enqueue_fill(-98765);self._errors.enqueue_fill(-98765)
        self._features.enqueue_fill(UInt64.MAX);self._values.enqueue_fill(POISON);self._points.enqueue_fill(POISON)
        self._headers.enqueue_fill(UInt64.MAX);self._output.enqueue_fill(POISON);self._point_output.enqueue_fill(POISON);self._state.enqueue_fill(UInt64.MAX)
        self.world.bodies._ctx.enqueue_function[initialize_box_state](self._state,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize()

    def detect(mut self) raises -> BoxBoxFrame:
        if self._closed:raise Error("Box/box detector closed")
        var legacy: DetectionFrame
        try:legacy=self.world.detect()
        except error:
            self.last_error=self.world.last_error;raise error
        self.world.bodies._ctx.enqueue_function[box_pairs](self.world._meta,self.world._bounds,self.world._statuses,self._flags,self._counts,self._errors,self._features,self._values,self._points,grid_dim=64,block_dim=64)
        self.world.bodies._ctx.enqueue_function[publish_boxes](self.world._meta,self.world._statuses,self._flags,self._counts,self._errors,self._features,self._values,self._points,
            self._headers,self._output,self._point_output,self._state,self._summary,self._pair_limit,self._point_limit,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize()
        with self._summary.map_to_host() as status:self.last_error=Int32(status[0])
        if self.last_error:raise Error("GPU box/box publication rejected="+String(self.last_error))
        var patches=List[BoxContactPatch]();var epoch=UInt64(0)
        with self._headers.map_to_host() as h,self._output.map_to_host() as v,self._point_output.map_to_host() as p,self._state.map_to_host() as state:
            assert_equal(h[0],UInt64.MAX);assert_equal(h[Int(self._pair_limit)*BB_HEADER+1],UInt64.MAX)
            assert_equal(v[0],POISON);assert_equal(v[Int(self._pair_limit)*7+1],POISON)
            assert_equal(p[0],POISON);assert_equal(p[Int(self._point_limit)*PATCH_FIELDS+1],POISON)
            assert_equal(state[0],UInt64.MAX);assert_equal(state[4],UInt64.MAX);epoch=UInt64(state[1])
            for i in range(Int(state[2])):
                var k=1+i*BB_HEADER;var g=1+i*7;var owner=UInt64(h[k+10]);var points=List[BoxContactPoint]()
                var key=PairKey(ShapeHandle(Int32(h[k]),UInt64(h[k+1]),owner),ShapeHandle(Int32(h[k+5]),UInt64(h[k+6]),owner),UInt64(h[k+2]),UInt64(h[k+7]),BodyHandle(Int32(h[k+3]),UInt64(h[k+4]),owner),BodyHandle(Int32(h[k+8]),UInt64(h[k+9]),owner))
                for j in range(Int(h[k+14])):
                    var q=1+(Int(h[k+13])+j)*PATCH_FIELDS
                    points.append(BoxContactPoint(Vec3(p[q],p[q+1],p[q+2]),Vec3(p[q+3],p[q+4],p[q+5]),Float64(p[q+6])))
                patches.append(BoxContactPatch(key,Vec3(v[g],v[g+1],v[g+2]),Vec3(v[g+3],v[g+4],v[g+5]),Float64(v[g+6]),Int32(h[k+11]),(h[k+12]&1)!=0,(h[k+12]&2)!=0,points^))
        return BoxBoxFrame(epoch,patches^,legacy^)

    def close(mut self) raises:
        if self._closed:return
        self.world.close();self._closed=True

    def debug_publication(mut self) raises -> List[UInt64]:
        """Explicit diagnostic readback; includes all tails, guards and epoch."""
        if self._closed:raise Error("Box/box detector closed")
        var result=List[UInt64]()
        with self._headers.map_to_host() as h,self._output.map_to_host() as v,self._point_output.map_to_host() as p,self._state.map_to_host() as state:
            for i in range(Int(self._pair_limit)*BB_HEADER+2):result.append(UInt64(h[i]))
            for i in range(Int(self._pair_limit)*7+2):result.append(float_bits(Float64(v[i])))
            for i in range(Int(self._point_limit)*PATCH_FIELDS+2):result.append(float_bits(Float64(p[i])))
            for i in range(5):result.append(UInt64(state[i]))
        return result^
