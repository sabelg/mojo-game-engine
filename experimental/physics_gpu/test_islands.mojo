"""G05a actual GPU components vs independent CPU flood fill; exact integer gates."""
from std.collections import List
from std.testing import assert_equal,assert_true,assert_raises
from mojo_game import RigidBody3D,MassProperties3D,Vec3
from experimental.physics_gpu.islands import GpuContactIslands,IslandFrame
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.collision import SphereCommand,BoxCommand,ShapeHandle

def body(p: Vec3,dynamic: Bool=True) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.sphere(2,.5) if dynamic else MassProperties3D.fixed(),position=p)
def sphere(mut islands: GpuContactIslands,p: Vec3,dynamic: Bool=True,radius: Float64=.5) raises -> BodyHandle:
    var handles=islands.world.bodies.submit([BodyCommand.create(body(p,dynamic))])
    _=islands.world.submit_shapes([SphereCommand.attach(handles[0],radius)])
    return handles[0]

def compare(f: IslandFrame,expected: List[Int32]) raises:
    assert_equal(len(f.members),len(expected))
    for i in range(len(expected)):assert_equal(f.members[i].root.slot,expected[i])

def smoke() raises:
    var islands=GpuContactIslands()
    var empty=islands.update();assert_equal(empty.report.islands,0);assert_equal(len(empty.members),0)
    _=sphere(islands,Vec3(0,0,0));_=sphere(islands,Vec3(.9,0,0));_=sphere(islands,Vec3(5,0,0))
    var frame=islands.update();compare(frame,[Int32(0),Int32(0),Int32(2)])
    assert_equal(frame.report.islands,2);assert_equal(frame.report.contacts,1)
    print("G05a first actual GPU islands: chain [0,1] -> root 0, isolated [2] -> root 2")
    islands.close()
def main() raises:
    smoke();topology_permutations();geometry_exclusions();static_policy();lifecycle_and_staleness();rejection();capacities()
    print("G05a actual GPU island construction qualified; sleep/warm-start/solver scheduling unchanged")

from std.memory import Pointer
from max.gpu import block_idx,block_dim,thread_idx
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import OracleBox,mixed_frame
from experimental.physics_gpu.island_kernels import ISLAND_BAD_BODY,ISLAND_BAD_COUNT,ISLAND_STALE_KEY,ISLAND_FULL,ISLAND_EPOCH_FULL,ISLAND_BAD_TOPOLOGY
from experimental.physics_gpu.shape_kernels import PAIR_HEADER,PAIRS,CONTACT_OVERFLOW,PAIR_OVERFLOW
from mojo_game import Quaternion

@fieldwise_init
struct Node(ImplicitlyCopyable,Movable):
    var handle: BodyHandle
    var value: RigidBody3D
    var live: Bool
    var kind: Int32
    var shape: ShapeHandle
    var revision: UInt64
    var radius: Float64
    var half: Vec3

def add(mut islands: GpuContactIslands,mut nodes: List[Node],p: Vec3,dynamic: Bool=True,kind: Int32=1,half: Vec3=Vec3(1,1,1)) raises -> Int:
    var value=body(p,dynamic);var handles=islands.world.bodies.submit([BodyCommand.create(value)])
    var shape=ShapeHandle(-1,0,0)
    if kind==1:
        var shapes=islands.world.submit_shapes([SphereCommand.attach(handles[0],.5)]);shape=shapes[0]
    elif kind==2:
        var shapes=islands.world.submit_boxes([BoxCommand.attach(handles[0],half)]);shape=shapes[0]
    nodes.append(Node(handles[0],value,True,kind,shape,1,.5,half))
    return len(nodes)-1

def move(mut islands: GpuContactIslands,mut nodes: List[Node],i: Int,p: Vec3) raises:
    nodes[i].value.position=p
    _=islands.world.bodies.submit([BodyCommand.update(nodes[i].handle,nodes[i].value)])

def same(a: BodyHandle,b: BodyHandle) raises:
    assert_equal(a.slot,b.slot);assert_equal(a.generation,b.generation);assert_equal(a.owner,b.owner)

def oracle(nodes: List[Node],f: IslandFrame) raises:
    # Independent geometry followed by queue-based flood fill, not union-find.
    # Never derive expected edges from GPU labels or GPU contact readback.
    var spheres=List[OracleSphere]();var boxes=List[OracleBox]();var by_slot=List[Int]()
    for _ in range(256):by_slot.append(-1)
    var labels=List[Int32]();var live=0
    for i in range(len(nodes)):
        labels.append(-1)
        var n=nodes[i]
        if not n.live:continue
        live+=1;by_slot[Int(n.handle.slot)]=i
        if n.kind==1:spheres.append(OracleSphere(n.shape,n.handle,n.revision,n.value,n.radius,Vec3(0,0,0)))
        elif n.kind==2:boxes.append(OracleBox(n.shape,n.handle,n.revision,n.value,n.half,Vec3(0,0,0),Quaternion()))
    var geometry=mixed_frame(spheres,boxes);var components=0
    for seed in range(len(nodes)):
        if not nodes[seed].live or nodes[seed].value.properties.mass==0 or labels[seed]!=-1:continue
        components+=1;var queue=List[Int]();queue.append(seed);labels[seed]=-2;var head=0;var minimum=nodes[seed].handle.slot
        while head<len(queue):
            var vertex=queue[head];head+=1;minimum=min(minimum,nodes[vertex].handle.slot)
            for c in geometry.contacts:
                var a=by_slot[Int(c.key.body_a.slot)];var b=by_slot[Int(c.key.body_b.slot)]
                if nodes[a].value.properties.mass==0 or nodes[b].value.properties.mass==0:continue
                var neighbor=b if a==vertex else a if b==vertex else -1
                if neighbor>=0 and labels[neighbor]==-1:labels[neighbor]=-2;queue.append(neighbor)
        for vertex in queue:labels[vertex]=minimum
    assert_equal(f.report.islands,Int32(components));assert_equal(f.report.live_bodies,Int32(live))
    assert_equal(f.report.contacts,Int32(len(geometry.contacts)));assert_equal(len(f.contacts),len(geometry.contacts));assert_equal(len(f.members),live)
    var last=Int32(-1)
    for m in f.members:
        assert_true(m.body.slot>last);last=m.body.slot
        var i=by_slot[Int(m.body.slot)];same(m.body,nodes[i].handle)
        assert_equal(m.dynamic,nodes[i].value.properties.mass>0);assert_equal(m.root.slot,labels[i])
        var gen=UInt64(0)
        if labels[i]>=0:gen=nodes[by_slot[Int(labels[i])]].handle.generation
        assert_equal(m.root.generation,gen);assert_equal(m.root.owner,m.body.owner)
    for i in range(len(f.contacts)):
        var actual=f.contacts[i];var expected=geometry.contacts[i].key
        assert_equal(actual.key.a.slot,expected.a.slot);assert_equal(actual.key.a.generation,expected.a.generation);assert_equal(actual.key.a.owner,expected.a.owner)
        assert_equal(actual.key.b.slot,expected.b.slot);assert_equal(actual.key.b.generation,expected.b.generation);assert_equal(actual.key.b.owner,expected.b.owner)
        assert_equal(actual.key.revision_a,expected.revision_a);assert_equal(actual.key.revision_b,expected.revision_b)
        same(actual.key.body_a,expected.body_a);same(actual.key.body_b,expected.body_b)
        var a=by_slot[Int(expected.body_a.slot)];var b=by_slot[Int(expected.body_b.slot)]
        var label=labels[a] if labels[a]>=0 else labels[b];assert_equal(actual.root.slot,label)
        assert_equal(actual.root.owner,expected.body_a.owner)
        var gen=UInt64(0)
        if label>=0:gen=nodes[by_slot[Int(label)]].handle.generation
        assert_equal(actual.root.generation,gen)
    # The graph operation must not integrate, solve, or otherwise modify bodies.


def reverse_records(headers: Pointer[UInt64,MutAnyOrigin],count: Int32):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=Int(count)//2:return
    var a=1+i*PAIR_HEADER;var b=1+(Int(count)-i-1)*PAIR_HEADER
    for f in range(PAIR_HEADER):
        var word=headers[unsafe_offset=a+f];headers[unsafe_offset=a+f]=headers[unsafe_offset=b+f];headers[unsafe_offset=b+f]=word

def overwrite(words: Pointer[UInt64,MutAnyOrigin],offset: Int32,value: UInt64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def duplicate(headers: Pointer[UInt64,MutAnyOrigin]):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:
        for f in range(PAIR_HEADER):headers[unsafe_offset=1+PAIR_HEADER+f]=headers[unsafe_offset=1+f]

def overwrite_int(words: Pointer[Int32,MutAnyOrigin],offset: Int32,value: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def corrupt_mass(current: Pointer[Float64,MutAnyOrigin],slot: Int32,value: Float64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:current[unsafe_offset=Int(slot)+1]=value

def exact(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])
def unchanged(a: Tuple[List[UInt64],List[UInt64],List[UInt64]],b: Tuple[List[UInt64],List[UInt64],List[UInt64]]) raises:
    exact(a[0],b[0]);exact(a[1],b[1]);exact(a[2],b[2])

def topology_permutations() raises:
    for reversed in [False,True]:
        var islands=GpuContactIslands();var nodes=List[Node]()
        for shift in [Float64(0),Float64(100)]:
            for j in range(4):
                var k=3-j if reversed else j
                _=add(islands,nodes,Vec3(shift+Float64(k)*.9,0,0))
        _=add(islands,nodes,Vec3(7,0,0));_=add(islands,nodes,Vec3(20,0,0),kind=0)
        var frame=islands.update();oracle(nodes,frame);assert_equal(frame.report.islands,4)
        var old=islands.debug_publication();var bytes_before=islands.world.bodies.raw();var counts=islands.world._detect_on_device()
        islands.world.bodies._ctx.enqueue_function[reverse_records](islands.world._contact_out,Int32(counts[1]),grid_dim=1,block_dim=64)
        islands.world.bodies._ctx.synchronize();_=islands._build_prepared(Int32(counts[1]));var reordered=islands.snapshot();oracle(nodes,reordered)
        var current=islands.debug_publication();exact(old[0],current[0]);exact(old[1],current[1])
        var bytes_after=islands.world.bodies.raw();assert_equal(len(bytes_before),len(bytes_after))
        for i in range(len(bytes_before)):assert_equal(bytes_before[i],bytes_after[i])
        assert_equal(frame.report.epoch,UInt64(1));assert_equal(reordered.report.epoch,UInt64(2))
        islands.close()
    var cycle=GpuContactIslands();var nodes=List[Node]()
    for p in [Vec3(0,0,0),Vec3(.9,0,0),Vec3(.9,.9,0),Vec3(0,.9,0)]:_=add(cycle,nodes,p)
    oracle(nodes,cycle.update());assert_equal(cycle.report().contacts,4);assert_equal(cycle.report().islands,1)
    cycle.close();print("G05a isolated/unshaped bodies, disconnected chains, cycle, creation/input permutations and body-byte preservation passed")

def static_policy() raises:
    var islands=GpuContactIslands();var nodes=List[Node]()
    _=add(islands,nodes,Vec3(0,-.1,0),False,2,Vec3(10,.1,10))
    _=add(islands,nodes,Vec3(-3,.45,0));_=add(islands,nodes,Vec3(3,.45,0))
    _=add(islands,nodes,Vec3(30,0,0),False);_=add(islands,nodes,Vec3(30.9,0,0),False)
    _=add(islands,nodes,Vec3(31.8,0,0));_=add(islands,nodes,Vec3(5,5,5),False,0)
    var frame=islands.update();oracle(nodes,frame);assert_equal(frame.report.islands,3)
    assert_equal(frame.members[1].root.slot,1);assert_equal(frame.members[2].root.slot,2)
    var static_contacts=0
    for c in frame.contacts:
        if c.root.slot<0:static_contacts+=1;assert_equal(c.root.generation,UInt64(0))
    assert_equal(static_contacts,1)
    islands.close();print("G05a shared fixed box, static-only contact and static chain never merge dynamic components passed")

def lifecycle_and_staleness() raises:
    var islands=GpuContactIslands();var nodes=List[Node]()
    _=add(islands,nodes,Vec3(0,0,0));_=add(islands,nodes,Vec3(.9,0,0));_=add(islands,nodes,Vec3(1.8,0,0))
    var initial=islands.update();oracle(nodes,initial)
    var old=islands.debug_publication();move(islands,nodes,1,Vec3(50,0,0))
    with assert_raises():_=islands._build_prepared(2)
    assert_equal(islands.last_error,ISLAND_BAD_TOPOLOGY);unchanged(old,islands.debug_publication())
    var separated=islands.update();oracle(nodes,separated);assert_equal(separated.report.islands,3)
    var cleared=islands.debug_publication();var contact_words=cleared[1].copy()
    for word in contact_words:assert_equal(word,UInt64.MAX)
    move(islands,nodes,1,Vec3(.9,0,0));oracle(nodes,islands.update());assert_equal(islands.report().islands,1)
    var old_handle=nodes[0].handle;_=islands.world.bodies.submit([BodyCommand.remove(old_handle)]);nodes[0].live=False
    oracle(nodes,islands.update());var replacement=add(islands,nodes,Vec3(0,0,0))
    assert_equal(nodes[replacement].handle.slot,old_handle.slot);assert_equal(nodes[replacement].handle.generation,old_handle.generation+1)
    var baseline=islands.debug_publication();var counts=islands.world._detect_on_device()
    islands.world.bodies._ctx.enqueue_function[overwrite](islands.world._contact_out,Int32(5),old_handle.generation,grid_dim=1,block_dim=1)
    islands.world.bodies._ctx.synchronize()
    with assert_raises():_=islands._build_prepared(Int32(counts[1]))
    assert_equal(islands.last_error,ISLAND_STALE_KEY);unchanged(baseline,islands.debug_publication())
    var final=islands.update();oracle(nodes,final)
    for m in final.members:
        if m.dynamic:assert_equal(m.root.generation,old_handle.generation+1)
    assert_equal(initial.members[0].body.generation,old_handle.generation);assert_equal(initial.report.epoch,UInt64(1))
    # Same pair topology, new revision: old header must still be rejected.
    var c=islands.world._detect_on_device();var before=islands.debug_publication()
    _=islands.world.submit_shapes([SphereCommand.reshape(nodes[replacement].shape,.55)]);nodes[replacement].revision+=1;nodes[replacement].radius=.55
    with assert_raises():_=islands._build_prepared(Int32(c[1]))
    assert_equal(islands.last_error,ISLAND_STALE_KEY);unchanged(before,islands.debug_publication());oracle(nodes,islands.update())
    islands.close();islands.close()
    with assert_raises():_=islands.build()
    with assert_raises():_=islands.snapshot()
    print("G05a creation/removal/split/rejoin, slot generation reuse, stale poses/keys/revisions, epochs and immutable/closed observations passed")

def rejection() raises:
    var islands=GpuContactIslands();var nodes=List[Node]()
    for i in range(3):_=add(islands,nodes,Vec3(Float64(i)*.9,0,0))
    oracle(nodes,islands.update());var baseline=islands.debug_publication()
    for mode in range(7):
        var counts=islands.world._detect_on_device();var count=Int32(counts[1]);var expected=ISLAND_STALE_KEY
        if mode==0:
            islands.world.bodies._ctx.enqueue_function[overwrite](islands.world._contact_out,Int32(1),UInt64.MAX,grid_dim=1,block_dim=1)
        elif mode==1:
            islands.world.bodies._ctx.enqueue_function[overwrite](islands.world._contact_out,Int32(11),UInt64(0),grid_dim=1,block_dim=1)
        elif mode==2:
            islands.world.bodies._ctx.enqueue_function[overwrite](islands.world._contact_out,Int32(2),UInt64(0),grid_dim=1,block_dim=1)
        elif mode==3:
            islands.world.bodies._ctx.enqueue_function[duplicate](islands.world._contact_out,grid_dim=1,block_dim=1);expected=ISLAND_BAD_TOPOLOGY
        elif mode==4:count=-1;expected=ISLAND_BAD_COUNT
        elif mode==5:count=Int32(PAIRS+1);expected=ISLAND_BAD_COUNT
        else:count-=1;expected=ISLAND_BAD_TOPOLOGY
        islands.world.bodies._ctx.synchronize()
        with assert_raises():_=islands._build_prepared(count)
        assert_equal(islands.last_error,expected);unchanged(baseline,islands.debug_publication())
    for corrupt_active in [False,True]:
        var counts=islands.world._detect_on_device()
        if corrupt_active:islands.world.bodies._ctx.enqueue_function[overwrite_int](islands.world.bodies._active,Int32(1),Int32(3),grid_dim=1,block_dim=1)
        else:islands.world.bodies._ctx.enqueue_function[overwrite](islands.world.bodies._generations,Int32(1),UInt64(0),grid_dim=1,block_dim=1)
        islands.world.bodies._ctx.synchronize()
        with assert_raises():_=islands._build_prepared(Int32(counts[1]))
        assert_equal(islands.last_error,ISLAND_BAD_BODY);unchanged(baseline,islands.debug_publication())
        islands.world.bodies._ctx.enqueue_function[overwrite_int](islands.world.bodies._active,Int32(1),Int32(1),grid_dim=1,block_dim=1)
        islands.world.bodies._ctx.enqueue_function[overwrite](islands.world.bodies._generations,Int32(1),UInt64(1),grid_dim=1,block_dim=1)
        islands.world.bodies._ctx.synchronize()
    var counts=islands.world._detect_on_device()
    islands.world.bodies._ctx.enqueue_function[corrupt_mass](islands.world.bodies._current,Int32(0),Float64("nan"),grid_dim=1,block_dim=1)
    islands.world.bodies._ctx.synchronize()
    with assert_raises():_=islands._build_prepared(Int32(counts[1]))
    assert_equal(islands.last_error,ISLAND_BAD_BODY);unchanged(baseline,islands.debug_publication())
    islands.world.bodies._ctx.enqueue_function[corrupt_mass](islands.world.bodies._current,Int32(0),Float64(2),grid_dim=1,block_dim=1)
    islands.world.bodies._ctx.enqueue_function[overwrite](islands._state,Int32(1),UInt64.MAX-1,grid_dim=1,block_dim=1)
    islands.world.bodies._ctx.synchronize();_=islands._build_prepared(Int32(counts[1]));assert_equal(islands.report().epoch,UInt64.MAX)
    var full_epoch=islands.debug_publication()
    with assert_raises():_=islands.build()
    assert_equal(islands.last_error,ISLAND_EPOCH_FULL);unchanged(full_epoch,islands.debug_publication())
    islands.world.bodies._ctx.enqueue_function[overwrite](islands._state,Int32(1),UInt64(1),grid_dim=1,block_dim=1)
    islands.world.bodies._ctx.synchronize();oracle(nodes,islands.update());islands.close()
    var limited=GpuContactIslands(island_limit=1);var n=List[Node]()
    _=add(limited,n,Vec3(0,0,0));_=add(limited,n,Vec3(.9,0,0));oracle(n,limited.update())
    var old=limited.debug_publication();move(limited,n,1,Vec3(5,0,0))
    with assert_raises():_=limited.build()
    assert_equal(limited.last_error,ISLAND_FULL);unchanged(old,limited.debug_publication())
    move(limited,n,1,Vec3(.9,0,0));oracle(n,limited.update());limited.close()
    for pair_failure in [False,True]:
        var small=GpuContactIslands(pair_limit=Int32(0 if pair_failure else 2016),contact_limit=Int32(2016 if pair_failure else 0));var n=List[Node]()
        _=add(small,n,Vec3(0,0,0));_=add(small,n,Vec3(.9,0,0));var before=small.debug_publication()
        with assert_raises():_=small.build()
        assert_equal(small.last_error,PAIR_OVERFLOW if pair_failure else CONTACT_OVERFLOW);unchanged(before,small.debug_publication());small.close()
    for limit in [Int32(-1),Int32(257)]:
        with assert_raises():_=GpuContactIslands(island_limit=limit)
    print("G05a invalid/count/namespace/duplicate/incomplete/body/epoch and island/contact/pair overflow reject without publication passed")

def capacities() raises:
    var empty=GpuContactIslands(pair_limit=0,contact_limit=0,island_limit=0);var n=List[Node]();oracle(n,empty.update());empty.close()
    var isolated=GpuContactIslands();var commands=List[BodyCommand]();var nodes=List[Node]()
    for i in range(256):commands.append(BodyCommand.create(body(Vec3(Float64(i)*4,0,0))))
    var handles=isolated.world.bodies.submit(commands)
    for i in range(256):nodes.append(Node(handles[i],body(Vec3(Float64(i)*4,0,0)),True,0,ShapeHandle(-1,0,0),1,.5,Vec3(0,0,0)))
    var all_isolated=isolated.update();oracle(nodes,all_isolated);assert_equal(all_isolated.report.islands,Int32(256));assert_equal(all_isolated.report.contacts,Int32(0));isolated.close()
    for fixed in [False,True]:
        var islands=GpuContactIslands();var nodes=List[Node]();var commands=List[BodyCommand]()
        for i in range(256):commands.append(BodyCommand.create(body(Vec3(0,0,0) if i<64 else Vec3(Float64(i)*4,0,0),not fixed)))
        var handles=islands.world.bodies.submit(commands);var shapes=List[SphereCommand]()
        for i in range(64):shapes.append(SphereCommand.attach(handles[i],.5))
        var shape_handles=islands.world.submit_shapes(shapes)
        for i in range(256):nodes.append(Node(handles[i],body(Vec3(0,0,0) if i<64 else Vec3(Float64(i)*4,0,0),not fixed),True,Int32(1 if i<64 else 0),shape_handles[i] if i<64 else ShapeHandle(-1,0,0),1,.5,Vec3(0,0,0)))
        var frame=islands.update();oracle(nodes,frame);assert_equal(frame.report.contacts,Int32(2016));assert_equal(frame.report.live_bodies,Int32(256))
        assert_equal(frame.report.islands,Int32(0 if fixed else 193))
        var storage=islands.world.bodies.storage_ids();oracle(nodes,islands.update());var after=islands.world.bodies.storage_ids();assert_equal(storage[0],after[0]);assert_equal(storage[1],after[1]);islands.close()
    print("G05a empty/zero limits and full 256 bodies/64 shapes/2016 contacts, unshaped singleton and static-only capacities/canaries passed")

def geometry_exclusions() raises:
    var islands=GpuContactIslands();var nodes=List[Node]()
    _=add(islands,nodes,Vec3(0,0,0));_=add(islands,nodes,Vec3(.9,.9,0))
    _=add(islands,nodes,Vec3(10,0,0),kind=2);_=add(islands,nodes,Vec3(10.1,0,0),kind=2)
    var excluded=islands.update();oracle(nodes,excluded);assert_equal(excluded.report.contacts,0);assert_equal(excluded.report.islands,4)
    move(islands,nodes,1,Vec3(.7,.7,0));var created=islands.update();oracle(nodes,created);assert_equal(created.report.contacts,1);assert_equal(created.report.islands,3)
    islands.close();print("G05a AABB-only false positives and excluded box/box pairs do not connect dynamic islands passed")
