"""G05a resident contact islands; separate from the qualified response owner.

Single-caller synchronous GPU construction. build reads back only status/counts;
snapshot/update are explicit diagnostic membership/key readbacks. Fixed bodies
anchor contacts but never connect dynamic islands. No sleep or solver scheduling.
"""
from max.gpu.host import DeviceBuffer
from std.collections import List
from std.testing import assert_equal
from .collision import GpuCollisionWorld,PairKey,ShapeHandle
from .lifecycle import BodyHandle
from .kernels import CAPACITY,STRIDE
from .shape_kernels import PAIRS,PAIR_HEADER,prepare_bounds,pair_geometry
from .island_kernels import *

@fieldwise_init
struct IslandReport(ImplicitlyCopyable,Movable):
    var epoch: UInt64
    var islands: Int32
    var live_bodies: Int32
    var contacts: Int32

@fieldwise_init
struct IslandMember(ImplicitlyCopyable,Movable):
    var body: BodyHandle
    var dynamic: Bool
    var root: BodyHandle

@fieldwise_init
struct IslandContact(ImplicitlyCopyable,Movable):
    var key: PairKey
    var root: BodyHandle

@fieldwise_init
struct IslandFrame(Movable):
    var report: IslandReport
    var members: List[IslandMember]
    var contacts: List[IslandContact]

struct GpuContactIslands(Movable):
    var world: GpuCollisionWorld
    var _members: DeviceBuffer[DType.uint64]
    var _contacts: DeviceBuffer[DType.uint64]
    var _pending_members: DeviceBuffer[DType.uint64]
    var _pending_contacts: DeviceBuffer[DType.uint64]
    var _parent: DeviceBuffer[DType.int32]
    var _seen: DeviceBuffer[DType.int32]
    var _state: DeviceBuffer[DType.uint64]
    var _summary: DeviceBuffer[DType.int32]
    var _contact_capacity: Int32
    var _island_limit: Int32
    var _closed: Bool
    var last_error: Int32
    var last_bad_record: Int32

    def __init__(out self,pair_limit: Int32=Int32(PAIRS),contact_limit: Int32=Int32(PAIRS),island_limit: Int32=Int32(CAPACITY)) raises:
        if island_limit<0 or island_limit>Int32(CAPACITY):raise Error("G05a island limit outside [0,256]")
        self.world=GpuCollisionWorld(pair_limit,contact_limit)
        self._contact_capacity=contact_limit;self._island_limit=island_limit;self._closed=False;self.last_error=0;self.last_bad_record=-1
        self._members=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](CAPACITY*MEMBER_WORDS+2)
        self._pending_members=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](CAPACITY*MEMBER_WORDS+2)
        self._contacts=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(contact_limit)*ISLAND_CONTACT_WORDS+2)
        self._pending_contacts=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(contact_limit)*ISLAND_CONTACT_WORDS+2)
        self._parent=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self._seen=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._state=self.world.bodies._ctx.enqueue_create_buffer[DType.uint64](6)
        self._summary=self.world.bodies._ctx.enqueue_create_buffer[DType.int32](2)
        self._members.enqueue_fill(UInt64.MAX);self._pending_members.enqueue_fill(UInt64.MAX)
        self._contacts.enqueue_fill(UInt64.MAX);self._pending_contacts.enqueue_fill(UInt64.MAX)
        self._parent.enqueue_fill(-98765);self._seen.enqueue_fill(-98765);self._state.enqueue_fill(UInt64.MAX)
        self.world.bodies._ctx.enqueue_function[initialize_islands](self._state,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize()

    def _open(self) raises:
        if self._closed:raise Error("G05a islands closed")
        self.world._open()

    def build(mut self) raises -> IslandReport:
        self._open();var counts: Tuple[Int,Int]
        try:counts=self.world._detect_on_device()
        except error:
            self.last_error=self.world.last_error;self.last_bad_record=-1;raise error
        return self._build_prepared(Int32(counts[1]))

    def _build_prepared(mut self,count: Int32) raises -> IslandReport:
        # Qualification/internal boundary: regenerate GPU truth to reject stale
        # poses/topology as well as generation/revision/namespace/duplicate keys.
        self._open()
        self.world.bodies._ctx.enqueue_function[prepare_bounds](self.world.bodies._current,self.world._meta,self.world._values,self.world._bounds,self.world._statuses,grid_dim=1,block_dim=64)
        self.world.bodies._ctx.enqueue_function[pair_geometry](self.world._meta,self.world._bounds,self.world._statuses,self.world._candidate_flags,self.world._contact_flags,self.world._geometry,grid_dim=64,block_dim=64)
        self.world.bodies._ctx.enqueue_function[construct_islands](self.world.bodies._current,self.world.bodies._active,self.world.bodies._generations,self.world.bodies._namespace,
            self.world._meta,self.world._statuses,self.world._contact_flags,self.world._contact_out,
            self._parent,self._seen,self._pending_members,self._pending_contacts,self._members,self._contacts,self._state,self._summary,
            count,self._contact_capacity,self._island_limit,grid_dim=1,block_dim=1)
        self.world.bodies._ctx.synchronize()
        with self._summary.map_to_host() as status:
            self.last_error=Int32(status[0]);self.last_bad_record=Int32(status[1])
        if self.last_error:raise Error("GPU island publication rejected; code="+String(self.last_error))
        return self.report()

    def report(mut self) raises -> IslandReport:
        self._open()
        with self._state.map_to_host() as state:
            assert_equal(state[0],UInt64.MAX);assert_equal(state[5],UInt64.MAX)
            return IslandReport(UInt64(state[1]),Int32(state[2]),Int32(state[3]),Int32(state[4]))

    def debug_publication(mut self) raises -> Tuple[List[UInt64],List[UInt64],List[UInt64]]:
        self._open();var members=List[UInt64]();var contacts=List[UInt64]();var state=List[UInt64]()
        with self._members.map_to_host() as m,self._contacts.map_to_host() as c,self._state.map_to_host() as s:
            assert_equal(m[0],UInt64.MAX);assert_equal(m[CAPACITY*MEMBER_WORDS+1],UInt64.MAX)
            assert_equal(c[0],UInt64.MAX);assert_equal(c[Int(self._contact_capacity)*ISLAND_CONTACT_WORDS+1],UInt64.MAX)
            assert_equal(s[0],UInt64.MAX);assert_equal(s[5],UInt64.MAX)
            for i in range(CAPACITY*MEMBER_WORDS+2):members.append(UInt64(m[i]))
            for i in range(Int(self._contact_capacity)*ISLAND_CONTACT_WORDS+2):contacts.append(UInt64(c[i]))
            for i in range(6):state.append(UInt64(s[i]))
        return members^,contacts^,state^

    def snapshot(mut self) raises -> IslandFrame:
        var data=self.debug_publication();var members=List[IslandMember]();var contacts=List[IslandContact]()
        var member_words=data[0].copy();var contact_words=data[1].copy();var state=data[2].copy()
        var report=IslandReport(state[1],Int32(state[2]),Int32(state[3]),Int32(state[4]))
        if report.epoch!=0:
            for i in range(CAPACITY):
                var m=1+i*MEMBER_WORDS
                if member_words[m]!=1:continue
                var label=member_words[m+3];var owner=member_words[m+5]
                members.append(IslandMember(BodyHandle(Int32(i),member_words[m+1],owner),member_words[m+2]!=0,
                    BodyHandle(Int32(label) if label!=NO_ISLAND else -1,member_words[m+4],owner)))
        for i in range(Int(report.contacts)):
            var h=1+i*ISLAND_CONTACT_WORDS;var owner=contact_words[h+10];var label=contact_words[h+PAIR_HEADER]
            var key=PairKey(ShapeHandle(Int32(contact_words[h]),contact_words[h+1],owner),ShapeHandle(Int32(contact_words[h+5]),contact_words[h+6],owner),contact_words[h+2],contact_words[h+7],
                BodyHandle(Int32(contact_words[h+3]),contact_words[h+4],owner),BodyHandle(Int32(contact_words[h+8]),contact_words[h+9],owner))
            contacts.append(IslandContact(key,BodyHandle(Int32(label) if label!=NO_ISLAND else -1,contact_words[h+PAIR_HEADER+1],owner)))
        return IslandFrame(report,members^,contacts^)

    def update(mut self) raises -> IslandFrame:
        _=self.build();return self.snapshot()

    def close(mut self) raises:
        if self._closed:return
        self.world.close();self._closed=True
