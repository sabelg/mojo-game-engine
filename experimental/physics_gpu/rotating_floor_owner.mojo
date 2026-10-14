"""Single-body experimental owner; updates precede atomic advance transactions."""
from std.collections import List
from max.gpu.host import DeviceContext,DeviceBuffer
from .rotating_floor_advance import rotating_floor_advance,commit_rotating_advance

struct GpuRotatingFloorAdvance(Movable):
    var _ctx: DeviceContext
    var _current: DeviceBuffer[DType.float64]
    var _candidate: DeviceBuffer[DType.float64]
    var _scratch: DeviceBuffer[DType.float64]
    var _result: DeviceBuffer[DType.float64]
    var _closed: Bool

    def __init__(out self,payload: List[Float64]) raises:
        self._ctx=DeviceContext()
        if String(self._ctx.name())!="NVIDIA GB10":raise Error("Qualified target is NVIDIA GB10")
        self._current=self._ctx.enqueue_create_buffer[DType.float64](192);self._candidate=self._ctx.enqueue_create_buffer[DType.float64](192);self._scratch=self._ctx.enqueue_create_buffer[DType.float64](96);self._result=self._ctx.enqueue_create_buffer[DType.float64](96);self._current.enqueue_fill(0);self._candidate.enqueue_fill(0);self._scratch.enqueue_fill(0);self._result.enqueue_fill(0);self._closed=False
        with self._current.map_to_host() as a:a[0]=-987654321.25;a[95]=-987654321.25;a[191]=-987654321.25;a[114]=-1
        with self._candidate.map_to_host() as a:a[0]=-987654321.25;a[95]=-987654321.25;a[191]=-987654321.25
        self.update(payload)

    def _fresh(mut self,payload: List[Float64]) raises:
        # Qualification-only reuse of allocations for a new isolated owner.
        self._current.enqueue_fill(0)
        with self._current.map_to_host() as a:a[0]=-987654321.25;a[95]=-987654321.25;a[191]=-987654321.25;a[114]=-1
        self.update(payload)

    def update(mut self,payload: List[Float64]) raises:
        if self._closed or len(payload)!=104:raise Error("Expected open owner and 104-word body/shape/input payload")
        # Accepted prior command: callers cannot write committed episode/history.
        with self._current.map_to_host() as a:
            for i in range(1,39):a[i]=payload[i]
            for i in range(40,44):a[i]=payload[i]
            for i in range(96,104):a[i]=payload[i]

    def advance(mut self) raises -> Int:
        if self._closed:raise Error("Rotating owner closed")
        self._ctx.enqueue_function[rotating_floor_advance](self._current,self._candidate,self._scratch,self._result,grid_dim=1,block_dim=1)
        self._ctx.enqueue_function[commit_rotating_advance](self._current,self._candidate,grid_dim=1,block_dim=1);self._ctx.synchronize()
        with self._candidate.map_to_host() as a:return Int(a[39])

    def snapshot(mut self) raises -> List[Float64]:
        var out=List[Float64]()
        with self._current.map_to_host() as a:
            for i in range(192):out.append(Float64(a[i]))
        return out^

    def report(mut self) raises -> List[Float64]:
        var out=List[Float64]()
        with self._candidate.map_to_host() as a:
            for i in range(192):out.append(Float64(a[i]))
        return out^

    def close(mut self):self._closed=True
