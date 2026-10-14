"""G03c GPU one-point pair/feature history, not a solver manifold or impulse cache."""
from max.gpu.host import DeviceBuffer
from std.collections import List
from std.testing import assert_equal
from mojo_game.math3d import Vec3
from .collision import GpuCollisionWorld,ShapeHandle,PairKey,SphereContact
from .lifecycle import BodyHandle
from .history_kernels import *
from .shape_kernels import PAIRS,POISON

@fieldwise_init
struct TrackedContact(ImplicitlyCopyable,Movable):
    var contact: SphereContact
    var identity: UInt64
    var age: UInt64
    var feature: UInt64
    var ambiguous: Bool
    var status: UInt64

@fieldwise_init
struct ContactFrame(Movable):
    var active: List[TrackedContact]
    var ended: List[TrackedContact]
    var epoch: UInt64

def decode_contact(words: List[UInt64],values: List[Float64],i: Int) -> TrackedContact:
    var h=1+i*WORDS;var g=1+i*GEOMETRY;var owner=words[h+10]
    var key=PairKey(ShapeHandle(Int32(words[h]),words[h+1],owner),ShapeHandle(Int32(words[h+5]),words[h+6],owner),words[h+2],words[h+7],
        BodyHandle(Int32(words[h+3]),words[h+4],owner),BodyHandle(Int32(words[h+8]),words[h+9],owner))
    var contact=SphereContact(key,Vec3(values[g],values[g+1],values[g+2]),values[g+3],Vec3(values[g+4],values[g+5],values[g+6]),Vec3(values[g+7],values[g+8],values[g+9]))
    return TrackedContact(contact,words[h+11],words[h+12],words[h+13],words[h+14]!=0,words[h+15])

struct GpuContactHistory(Movable):
    var world: GpuCollisionWorld
    var _current: DeviceBuffer[DType.uint64]
    var _values: DeviceBuffer[DType.float64]
    var _pending: DeviceBuffer[DType.uint64]
    var _pending_values: DeviceBuffer[DType.float64]
    var _diagnostic: DeviceBuffer[DType.uint64]
    var _diagnostic_values: DeviceBuffer[DType.float64]
    var _events: DeviceBuffer[DType.uint64]
    var _event_values: DeviceBuffer[DType.float64]
    var _features: DeviceBuffer[DType.uint64]
    var _index_map: DeviceBuffer[DType.int32]
    var _matched: DeviceBuffer[DType.int32]
    var _state: DeviceBuffer[DType.uint64]
    var _diagnostic_state: DeviceBuffer[DType.uint64]
    var _summary: DeviceBuffer[DType.int32]
    var _capacity: Int32
    var _event_capacity: Int32
    var _closed: Bool
    var last_error: Int32

    def __init__(out self,pair_limit: Int32=256,contact_limit: Int32=256,capacity: Int32=256,event_capacity: Int32=512) raises:
        if capacity<0 or capacity>Int32(PAIRS) or event_capacity<0 or event_capacity>Int32(PAIRS*2):raise Error("G03c history/event capacity outside [0,2016]/[0,4032]")
        self.world=GpuCollisionWorld(pair_limit,contact_limit);self._capacity=capacity;self._event_capacity=event_capacity;self._closed=False;self.last_error=0
        self._current=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*WORDS+2)
        self._values=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)*GEOMETRY+2)
        self._pending=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*WORDS+2)
        self._pending_values=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)*GEOMETRY+2)
        self._diagnostic=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(capacity)*WORDS+2)
        self._diagnostic_values=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(capacity)*GEOMETRY+2)
        self._events=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(event_capacity)*WORDS+2)
        self._event_values=self.world.bodies._ctx.enqueue_create_buffer[DType.float64](Int(event_capacity)*GEOMETRY+2)
        self._features=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](PAIRS*2+2)
        self._index_map=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._matched=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](Int(capacity)+2)
        self._state=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](5)
        self._diagnostic_state=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](5)
        self._summary=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](5)
        self._current.enqueue_fill(UInt64.MAX);self._pending.enqueue_fill(UInt64.MAX);self._diagnostic.enqueue_fill(UInt64.MAX);self._events.enqueue_fill(UInt64.MAX)
        self._values.enqueue_fill(POISON);self._pending_values.enqueue_fill(POISON);self._diagnostic_values.enqueue_fill(POISON);self._event_values.enqueue_fill(POISON)
        self._state.enqueue_fill(UInt64.MAX);self._diagnostic_state.enqueue_fill(UInt64.MAX);self._features.enqueue_fill(UInt64.MAX)
        self._index_map.enqueue_fill(-98765);self._matched.enqueue_fill(-98765)
        self.world.bodies._ctx.enqueue_function[initialize_history](self._state,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize()

    def _open(self) raises:
        if self._closed:raise Error("G03c history closed")
        self.world._open()

    def update(mut self) raises -> ContactFrame:
        self._open();var counts: Tuple[Int,Int]
        try:counts=self.world._detect_on_device()
        except error:
            self.last_error=self.world.last_error
            raise error
        var count=Int32(counts[1])
        self.world.bodies._ctx.enqueue_function[contact_features](self.world._meta,self.world._bounds,self.world._contact_out,self._features,count,grid_dim=32,block_dim=64)
        self.world.bodies._ctx.enqueue_function[history_transaction](self.world._contact_out,self.world._contact_values,self._features,
            self._current,self._values,self._pending,self._pending_values,self._events,self._event_values,self._state,self._index_map,self._matched,self._summary,
            count,self._capacity,self._event_capacity,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize();var ended=Int(0)
        with self._summary.map_to_host() as summary:
            self.last_error=Int32(summary[0]);ended=Int(summary[3])
        if self.last_error:raise Error("GPU history publication rejected; code="+String(self.last_error))
        var words=List[UInt64]();var values=List[Float64]();var epoch=UInt64(0)
        with self._events.map_to_host() as h,self._event_values.map_to_host() as g,self._state.map_to_host() as state:
            assert_equal(h[0],UInt64.MAX);assert_equal(h[Int(self._event_capacity)*WORDS+1],UInt64.MAX)
            assert_equal(g[0],POISON);assert_equal(g[Int(self._event_capacity)*GEOMETRY+1],POISON)
            assert_equal(state[0],UInt64.MAX);assert_equal(state[4],UInt64.MAX);epoch=UInt64(state[2])
            for i in range((Int(count)+ended)*WORDS+1):words.append(UInt64(h[i]))
            for i in range((Int(count)+ended)*GEOMETRY+1):values.append(Float64(g[i]))
        var active=List[TrackedContact]();var removed=List[TrackedContact]()
        for i in range(Int(count)):active.append(decode_contact(words,values,i))
        for i in range(ended):removed.append(decode_contact(words,values,Int(count)+i))
        return ContactFrame(active^,removed^,epoch)

    def debug_cache(mut self) raises -> Tuple[List[UInt64],List[Float64],List[UInt64]]:
        self._open()
        self.world.bodies._ctx.enqueue_function[history_snapshot](self._current,self._values,self._state,self._diagnostic,self._diagnostic_values,self._diagnostic_state,self._capacity,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize();var words=List[UInt64]();var values=List[Float64]();var state=List[UInt64]()
        with self._diagnostic.map_to_host() as h,self._diagnostic_values.map_to_host() as g,self._diagnostic_state.map_to_host() as s:
            for i in range(Int(self._capacity)*WORDS+2):words.append(UInt64(h[i]))
            for i in range(Int(self._capacity)*GEOMETRY+2):values.append(Float64(g[i]))
            for i in range(5):state.append(UInt64(s[i]))
        return words^,values^,state^

    def close(mut self) raises:
        if self._closed:return
        self.world.close();self._closed=True
