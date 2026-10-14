"""G03a actual GPU shapes/candidates/contacts versus independent CPU oracle."""
from std.collections import List
from std.memory import Pointer
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.collision import GpuCollisionWorld,SphereCommand,ShapeHandle,PairKey,DetectionFrame
from experimental.physics_gpu.shape_kernels import SHAPES,PAIRS,SHAPE_STALE,SHAPE_RANGE,BAD_SHAPE,DUPLICATE_BODY,SHAPE_FULL,PAIR_OVERFLOW,CONTACT_OVERFLOW,GEOMETRY_RANGE,SHAPE_WORLD,BODY_STALE,REVISION_FULL
from experimental.physics_gpu.contact_oracle import OracleSphere,oracle_frame

def body(p: Vec3) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.sphere(2,.5),position=p)
def packet(c: SphereCommand) -> List[SphereCommand]:
    var v: List[SphereCommand]=[c];return v^
def body_packet(c: BodyCommand) -> List[BodyCommand]:
    var v: List[BodyCommand]=[c];return v^
def near(a: Float64,b: Float64) raises:
    assert_true(abs(a-b)<=1e-9+1e-12*abs(b))
def vector(a: Vec3,b: Vec3) raises:
    near(a.x,b.x);near(a.y,b.y);near(a.z,b.z)
def key_equal(a: PairKey,b: PairKey) raises:
    assert_equal(a.a.slot,b.a.slot);assert_equal(a.b.slot,b.b.slot)
    assert_equal(a.a.generation,b.a.generation);assert_equal(a.b.generation,b.b.generation)
    assert_equal(a.a.owner,b.a.owner);assert_equal(a.b.owner,b.b.owner)
    assert_equal(a.revision_a,b.revision_a);assert_equal(a.revision_b,b.revision_b)
    assert_equal(a.body_a.slot,b.body_a.slot);assert_equal(a.body_b.slot,b.body_b.slot)
    assert_equal(a.body_a.generation,b.body_a.generation);assert_equal(a.body_b.generation,b.body_b.generation)
def compare_frames(actual: DetectionFrame,expected: DetectionFrame) raises:
    assert_equal(len(actual.candidates),len(expected.candidates));assert_equal(len(actual.contacts),len(expected.contacts))
    var previous=Int(-1)
    for i in range(len(actual.candidates)):
        var k=actual.candidates[i];assert_true(k.a.slot<k.b.slot)
        var order=Int(k.a.slot)*64+Int(k.b.slot);assert_true(order>previous);previous=order
        key_equal(k,expected.candidates[i])
    for i in range(len(actual.contacts)):
        var a=actual.contacts[i];var b=expected.contacts[i];key_equal(a.key,b.key)
        vector(a.normal,b.normal);near(a.separation,b.separation);vector(a.witness_a,b.witness_a);vector(a.witness_b,b.witness_b)
        assert_true(abs(a.normal.dot(a.normal)-1)<=1e-12)
        assert_true(a.separation<=0)

def add(mut world: GpuCollisionWorld,b: RigidBody3D,radius: Float64,offset: Vec3=Vec3(0,0,0)) raises -> OracleSphere:
    var handles=world.bodies.submit(body_packet(BodyCommand.create(b)))
    var shapes=world.submit_shapes(packet(SphereCommand.attach(handles[0],radius,offset)))
    return OracleSphere(shapes[0],handles[0],1,b,radius,offset)

def boundary_geometry() raises:
    for x in [3.0,2.0,2.0-1e-8,2.0+1e-8,0.0,1e-12]:
        var world=GpuCollisionWorld();var spheres=List[OracleSphere]()
        spheres.append(add(world,body(Vec3(0,0,0)),1))
        spheres.append(add(world,body(Vec3(x,0,0)),1))
        var before=world.bodies.raw();var actual=world.detect();compare_frames(actual,oracle_frame(spheres))
        var again=world.detect();compare_frames(again,oracle_frame(spheres))
        var after=world.bodies.raw()
        for i in range(len(before)):assert_equal(before[i],after[i])
        if x==0:assert_equal(actual.contacts[0].normal.x,Float64(1))
        world.close()
    var diagonal=GpuCollisionWorld();var v=List[OracleSphere]()
    v.append(add(diagonal,body(Vec3(0,0,0)),1));v.append(add(diagonal,body(Vec3(1.5,1.5,0)),1))
    var d=diagonal.detect();compare_frames(d,oracle_frame(v));assert_equal(len(d.candidates),1);assert_equal(len(d.contacts),0);diagonal.close()
    var tangent=GpuCollisionWorld();var t=List[OracleSphere]()
    t.append(add(tangent,body(Vec3(0,0,0)),2));t.append(add(tangent,body(Vec3(3,4,0)),3))
    compare_frames(tangent.detect(),oracle_frame(t));tangent.close()
    for radius in [1e-6,1e4]:
        var world=GpuCollisionWorld();var s=List[OracleSphere]()
        s.append(add(world,body(Vec3(0,0,0)),radius));s.append(add(world,body(Vec3(radius*2,0,0)),radius))
        compare_frames(world.detect(),oracle_frame(s));world.close()
    print("G03a GPU separation/touch/overlap/coincident/near-coincident, AABB false positives and radius boundaries passed")

def completeness_and_offsets() raises:
    var world=GpuCollisionWorld(2016,2016);var spheres=List[OracleSphere]()
    for i in range(36):
        var b=body(Vec3(Float64(i%6)*1.3,Float64((i//6)%3)*1.2,Float64(i//18)*1.1))
        b.orientation=Quaternion.axis_angle(Vec3(1,2,3),Float64(i)*.11)
        b.angular_velocity=Vec3(.02,.1,-.03)
        spheres.append(add(world,b,.55+Float64(i%4)*.15,Vec3(.15,-.1,.2)))
    var storage=world.bodies.storage_ids()
    compare_frames(world.detect(),oracle_frame(spheres))
    for frame in range(4):
        assert_equal(world.bodies.step(1.0/60,Vec3(0,0,0)),0)
        for i in range(len(spheres)):_=spheres[i].body.integrate(1.0/60,Vec3(0,0,0))
        compare_frames(world.detect(),oracle_frame(spheres))
    var after=world.bodies.storage_ids();assert_equal(storage[0],after[0]);assert_equal(storage[1],after[1])
    world.close();print("G03a GPU candidate completeness/uniqueness/order and rotated local-offset CPU oracle passed")

def shape_reject(mut world: GpuCollisionWorld,commands: List[SphereCommand],code: Int32) raises:
    var before=world.debug_registry();var bodies=world.bodies.raw();var metadata=world.bodies.metadata()
    var epoch=world._epoch;var returned=False
    with assert_raises():
        _=world.submit_shapes(commands)
        returned=True
    assert_true(not returned);assert_equal(world._epoch,epoch)
    assert_equal(world.last_error,code)
    var after=world.debug_registry();var after_bodies=world.bodies.raw();var after_metadata=world.bodies.metadata()
    for i in range(len(before[0])):assert_equal(before[0][i],after[0][i])
    for i in range(len(before[1])):assert_equal(before[1][i],after[1][i])
    for i in range(len(bodies)):assert_equal(bodies[i],after_bodies[i])
    for i in range(len(metadata)):assert_equal(metadata[i],after_metadata[i])

def lifecycle_and_invalid() raises:
    var world=GpuCollisionWorld();var a=add(world,body(Vec3(0,0,0)),1);var b=add(world,body(Vec3(1,0,0)),1)
    var first=world.detect();assert_equal(first.contacts[0].key.revision_a,UInt64(1))
    _=world.submit_shapes(packet(SphereCommand.reshape(a.shape,.9)))
    var revised=world.detect();assert_equal(revised.contacts[0].key.revision_a,UInt64(2))
    shape_reject(world,packet(SphereCommand.attach(a.body_handle,1)),DUPLICATE_BODY)
    var raw=SphereCommand.reshape(a.shape,1);raw.radius=0
    shape_reject(world,packet(raw),BAD_SHAPE)
    raw=SphereCommand.reshape(a.shape,1);raw.kind=99
    shape_reject(world,packet(raw),BAD_SHAPE)
    var mixed: List[SphereCommand]=[SphereCommand.detach(a.shape),SphereCommand.reshape(a.shape,1)]
    shape_reject(world,mixed,SHAPE_STALE)
    shape_reject(world,packet(SphereCommand.detach(ShapeHandle(-1,a.shape.generation,a.shape.owner))),SHAPE_RANGE)
    with assert_raises():_=SphereCommand.attach(a.body_handle,-1)
    _=world.bodies.submit(body_packet(BodyCommand.remove(a.body_handle)))
    assert_equal(len(world.detect().contacts),0)
    var new_body=world.bodies.submit(body_packet(BodyCommand.create(body(Vec3(0,0,0)))))
    assert_equal(new_body[0].slot,a.body_handle.slot)
    var attached=world.submit_shapes(packet(SphereCommand.attach(new_body[0],1)))
    assert_equal(attached[0].slot,a.shape.slot);assert_equal(attached[0].generation,a.shape.generation+1)
    shape_reject(world,packet(SphereCommand.reshape(a.shape,2)),SHAPE_STALE)
    var again=world.detect();assert_equal(len(again.contacts),1);assert_equal(again.contacts[0].key.body_a.generation,new_body[0].generation)
    world.close()
    with assert_raises():_=world.detect()
    print("G03a GPU shape revisions, ownership/reuse/orphan invalidation and transactional invalid-input checks passed")

def capacity_and_ranges() raises:
    var dense=GpuCollisionWorld(2016,2016)
    for _ in range(64):_=add(dense,body(Vec3(0,0,0)),1)
    var full=dense.detect();assert_equal(len(full.candidates),2016);assert_equal(len(full.contacts),2016)
    var extra=dense.bodies.submit(body_packet(BodyCommand.create(body(Vec3(0,0,0)))))
    shape_reject(dense,packet(SphereCommand.attach(extra[0],1)),SHAPE_FULL)
    dense.close()
    for mode in range(2):
        var limited=GpuCollisionWorld(Int32(0 if mode==0 else 10),Int32(0 if mode==1 else 10))
        _=add(limited,body(Vec3(0,0,0)),1);_=add(limited,body(Vec3(1,0,0)),1)
        var before=limited.bodies.raw()
        with assert_raises():_=limited.detect()
        assert_equal(limited.last_error,PAIR_OVERFLOW if mode==0 else CONTACT_OVERFLOW)
        var after=limited.bodies.raw()
        for i in range(len(before)):assert_equal(before[i],after[i])
        limited.close()
    var range_world=GpuCollisionWorld();_=add(range_world,body(Vec3(1e9+1,0,0)),1)
    with assert_raises():_=range_world.detect()
    assert_equal(range_world.last_error,GEOMETRY_RANGE);range_world.close()
    print("G03a GPU 64-shape/2016-pair capacity, explicit pair/contact overflow and center-range failure passed")

# Test-only device setup makes UInt64 boundary fixtures finite. It changes only
# active-slot counters; no production API hook, allocator or ownership bypass is
# added. Expected transitions below are explicit, not calculated by GPU helpers.
def seed_shape_counters(meta: Pointer[UInt64,MutAnyOrigin],slot: Int32,generation: UInt64,revision: UInt64):
    var s=Int(slot)+1
    meta[unsafe_offset=66+s]=generation
    meta[unsafe_offset=132+s]=revision

def seed_active_counters(mut world: GpuCollisionWorld,handle: ShapeHandle,generation: UInt64,revision: UInt64) raises:
    var before=world.debug_registry();var s=Int(handle.slot)+1
    assert_true(handle.slot>=0 and handle.slot<64)
    assert_equal(before[0][s],UInt64(1));assert_equal(before[0][66+s],handle.generation)
    assert_equal(before[0][330+s],handle.owner)
    assert_true(generation>=handle.generation and revision>=before[0][132+s])
    world.bodies._ctx.enqueue_function[seed_shape_counters](world._meta,handle.slot,generation,revision,grid_dim=1,block_dim=1)
    world.bodies._ctx.synchronize()
    var after=world.debug_registry()
    for i in range(len(before[0])):
        assert_equal(after[0][i],generation if i==66+s else revision if i==132+s else before[0][i])
    for i in range(len(before[1])):assert_equal(after[1][i],before[1][i])

def expect_slot(mut world: GpuCollisionWorld,slot: Int,state: UInt64,generation: UInt64,revision: UInt64) raises:
    var raw=world.debug_registry();var s=slot+1
    assert_equal(raw[0][s],state);assert_equal(raw[0][66+s],generation);assert_equal(raw[0][132+s],revision)
    # Explicit independent layout/guard expectations. Inactive descriptors are
    # cleared, and permanent retirement is state 2 with generation MAX, never 0.
    if state!=1:
        for f in range(3,7):assert_equal(raw[0][f*66+s],UInt64(0))
        for f in range(4):assert_equal(raw[1][f*66+s],Float64(-987654321.25))
    for f in range(7):
        assert_equal(raw[0][f*66],UInt64.MAX);assert_equal(raw[0][f*66+65],UInt64.MAX)
    for f in range(4):
        assert_equal(raw[1][f*66],Float64(-987654321.25));assert_equal(raw[1][f*66+65],Float64(-987654321.25))

def foreign_shape_namespaces() raises:
    var world=GpuCollisionWorld();var a=add(world,body(Vec3(0,0,0)),1);var b=add(world,body(Vec3(1,0,0)),1)
    var other=GpuCollisionWorld();var foreign=add(other,body(Vec3(0,0,0)),1)
    assert_equal(a.shape.slot,Int32(0));assert_equal(foreign.shape.slot,Int32(0))
    assert_equal(a.shape.generation,UInt64(1));assert_equal(foreign.shape.generation,UInt64(1))
    assert_true(a.shape.owner!=0 and foreign.shape.owner!=0 and a.shape.owner!=foreign.shape.owner)
    var expected: List[OracleSphere]=[a,b];var foreign_expected: List[OracleSphere]=[foreign]
    var published=world.detect();compare_frames(published,oracle_frame(expected))
    var other_before=other.debug_registry();var other_bodies=other.bodies.raw();var other_metadata=other.bodies.metadata()
    shape_reject(world,packet(SphereCommand.detach(foreign.shape)),SHAPE_WORLD)
    assert_equal(world.last_bad_command,Int32(0))
    shape_reject(world,packet(SphereCommand.reshape(foreign.shape,.8)),SHAPE_WORLD)
    shape_reject(world,packet(SphereCommand.detach(ShapeHandle(a.shape.slot,a.shape.generation,0))),SHAPE_WORLD)
    shape_reject(world,packet(SphereCommand.attach(foreign.body_handle,1)),BODY_STALE)
    var mixed: List[SphereCommand]=[SphereCommand.reshape(a.shape,.8),SphereCommand.detach(foreign.shape)]
    shape_reject(world,mixed,SHAPE_WORLD);assert_equal(world.last_bad_command,Int32(1))
    compare_frames(published,oracle_frame(expected));compare_frames(world.detect(),oracle_frame(expected))
    var other_after=other.debug_registry()
    for i in range(len(other_before[0])):assert_equal(other_before[0][i],other_after[0][i])
    for i in range(len(other_before[1])):assert_equal(other_before[1][i],other_after[1][i])
    var other_after_bodies=other.bodies.raw();var other_after_metadata=other.bodies.metadata()
    for i in range(len(other_bodies)):assert_equal(other_bodies[i],other_after_bodies[i])
    for i in range(len(other_metadata)):assert_equal(other_metadata[i],other_after_metadata[i])
    compare_frames(other.detect(),oracle_frame(foreign_expected))
    world.close();other.close()
    print("G03a GPU foreign shape detach/reshape, foreign body attach and mixed-command publication rollback passed")

def shape_counter_exhaustion() raises:
    var world=GpuCollisionWorld();var a=add(world,body(Vec3(0,0,0)),1);var b=add(world,body(Vec3(1,0,0)),1)
    var owner=a.shape.owner
    seed_active_counters(world,a.shape,UInt64.MAX-1,UInt64.MAX-1)
    a.shape=ShapeHandle(0,UInt64.MAX-1,owner);a.revision=UInt64.MAX-1
    var expected: List[OracleSphere]=[a,b]
    compare_frames(world.detect(),oracle_frame(expected))
    _=world.submit_shapes(packet(SphereCommand.reshape(a.shape,.9)))
    a.radius=.9;a.revision=UInt64.MAX;expected[0]=a
    expect_slot(world,0,1,UInt64.MAX-1,UInt64.MAX)
    compare_frames(world.detect(),oracle_frame(expected))
    shape_reject(world,packet(SphereCommand.reshape(a.shape,.8)),REVISION_FULL)
    var revision_mixed: List[SphereCommand]=[SphereCommand.detach(b.shape),SphereCommand.reshape(a.shape,.8)]
    shape_reject(world,revision_mixed,REVISION_FULL);assert_equal(world.last_bad_command,Int32(1))
    compare_frames(world.detect(),oracle_frame(expected))
    _=world.submit_shapes(packet(SphereCommand.detach(a.shape)))
    expect_slot(world,0,0,UInt64.MAX,0)
    shape_reject(world,packet(SphereCommand.detach(a.shape)),SHAPE_STALE)
    var reuse_rollback: List[SphereCommand]=[SphereCommand.attach(a.body_handle,1),SphereCommand.reshape(a.shape,.8)]
    shape_reject(world,reuse_rollback,SHAPE_STALE);assert_equal(world.last_bad_command,Int32(1))
    expect_slot(world,0,0,UInt64.MAX,0)
    var final_generation=world.submit_shapes(packet(SphereCommand.attach(a.body_handle,1)))
    assert_equal(final_generation[0].slot,Int32(0));assert_equal(final_generation[0].generation,UInt64.MAX)
    a.shape=ShapeHandle(0,UInt64.MAX,owner);a.radius=1;a.revision=1;expected[0]=a
    expect_slot(world,0,1,UInt64.MAX,1);compare_frames(world.detect(),oracle_frame(expected))
    for generation in [UInt64(0),UInt64(1),UInt64.MAX-1]:
        shape_reject(world,packet(SphereCommand.detach(ShapeHandle(0,generation,owner))),SHAPE_STALE)
    var exhausted=a.shape
    _=world.submit_shapes(packet(SphereCommand.detach(exhausted)))
    expect_slot(world,0,2,UInt64.MAX,0)
    var only_b: List[OracleSphere]=[b];compare_frames(world.detect(),oracle_frame(only_b))
    for generation in [UInt64(0),UInt64(1),UInt64.MAX]:
        var dead=ShapeHandle(0,generation,owner)
        shape_reject(world,packet(SphereCommand.detach(dead)),SHAPE_STALE)
        shape_reject(world,packet(SphereCommand.reshape(dead,1)),SHAPE_STALE)
    var next=world.submit_shapes(packet(SphereCommand.attach(a.body_handle,1)))
    assert_equal(next[0].slot,Int32(2));assert_equal(next[0].generation,UInt64(1))
    a.shape=ShapeHandle(2,1,owner);expected[0]=a
    compare_frames(world.detect(),oracle_frame(expected));expect_slot(world,0,2,UInt64.MAX,0)
    _=world.submit_shapes(packet(SphereCommand.detach(a.shape)))
    var reattached=world.submit_shapes(packet(SphereCommand.attach(a.body_handle,1)))
    assert_equal(reattached[0].slot,Int32(2));assert_equal(reattached[0].generation,UInt64(2))
    a.shape=ShapeHandle(2,2,owner);expected[0]=a
    compare_frames(world.detect(),oracle_frame(expected));expect_slot(world,0,2,UInt64.MAX,0)
    # Remove/create the attached body before a shape transaction. The ordinary
    # live slot is reclaimed with generation 3, while retired slot 0 stays dead.
    _=world.bodies.submit(body_packet(BodyCommand.remove(a.body_handle)))
    var new_body=body(Vec3(.1,0,0));var replacement=world.bodies.submit(body_packet(BodyCommand.create(new_body)))
    assert_equal(replacement[0].slot,Int32(0));assert_equal(replacement[0].generation,UInt64(2))
    var attached=world.submit_shapes(packet(SphereCommand.attach(replacement[0],1)))
    assert_equal(attached[0].slot,Int32(2));assert_equal(attached[0].generation,UInt64(3))
    a=OracleSphere(ShapeHandle(2,3,owner),BodyHandle(0,2,owner),1,new_body,1,Vec3(0,0,0));expected[0]=a
    shape_reject(world,packet(SphereCommand.reshape(exhausted,1)),SHAPE_STALE)
    expect_slot(world,0,2,UInt64.MAX,0);compare_frames(world.detect(),oracle_frame(expected))
    # Retirement consumes a slot permanently: 63 live shapes is full with one
    # retired slot. Expected remaining allocations are explicit slots 3..63.
    for slot in range(3,64):
        var extra=add(world,body(Vec3(Float64(slot)*4,0,0)),1)
        assert_equal(extra.shape.slot,Int32(slot));assert_equal(extra.shape.generation,UInt64(1))
        expected.append(extra)
    var spare=world.bodies.submit(body_packet(BodyCommand.create(body(Vec3(300,0,0)))))
    shape_reject(world,packet(SphereCommand.attach(spare[0],1)),SHAPE_FULL)
    expect_slot(world,0,2,UInt64.MAX,0);compare_frames(world.detect(),oracle_frame(expected))
    world.close()
    print("G03a GPU revision MAX rejection, generation MAX-1/MAX transitions, detach retirement and permanent 63-live-shape capacity passed")

def exhausted_shape_orphan_retirement() raises:
    var world=GpuCollisionWorld();var a=add(world,body(Vec3(0,0,0)),1);var b=add(world,body(Vec3(1,0,0)),1)
    var owner=a.shape.owner
    seed_active_counters(world,a.shape,UInt64.MAX,1)
    a.shape=ShapeHandle(0,UInt64.MAX,owner)
    var old_expected: List[OracleSphere]=[a,b];var published=world.detect()
    compare_frames(published,oracle_frame(old_expected))
    _=world.bodies.submit(body_packet(BodyCommand.remove(a.body_handle)))
    var replacement_body=body(Vec3(.2,0,0))
    var replacement=world.bodies.submit(body_packet(BodyCommand.create(replacement_body)))
    assert_equal(replacement[0].slot,Int32(0));assert_equal(replacement[0].generation,UInt64(2))
    # Orphan pruning is also transactional: a foreign command after scratch
    # pruning must not prematurely retire the published active MAX slot.
    shape_reject(world,packet(SphereCommand.reshape(ShapeHandle(0,UInt64.MAX,0),1)),SHAPE_WORLD)
    expect_slot(world,0,1,UInt64.MAX,1)
    # Old body slot has already been reused. Empty detection reconciliation must
    # retire the exhausted shape rather than attach it to the new body identity.
    var remaining: List[OracleSphere]=[b]
    compare_frames(world.detect(),oracle_frame(remaining));expect_slot(world,0,2,UInt64.MAX,0)
    compare_frames(published,oracle_frame(old_expected))
    shape_reject(world,packet(SphereCommand.detach(a.shape)),SHAPE_STALE)
    shape_reject(world,packet(SphereCommand.reshape(a.shape,1)),SHAPE_STALE)
    shape_reject(world,packet(SphereCommand.attach(a.body_handle,1)),BODY_STALE)
    var attached=world.submit_shapes(packet(SphereCommand.attach(replacement[0],1)))
    assert_equal(attached[0].slot,Int32(2));assert_equal(attached[0].generation,UInt64(1))
    var current=OracleSphere(ShapeHandle(2,1,owner),BodyHandle(0,2,owner),1,replacement_body,1,Vec3(0,0,0))
    var expected: List[OracleSphere]=[b,current]
    compare_frames(world.detect(),oracle_frame(expected));expect_slot(world,0,2,UInt64.MAX,0)
    # Ordinary detach/reuse and another body lifecycle transition cannot revive
    # an exhausted slot or cause its old contact identity to appear.
    _=world.submit_shapes(packet(SphereCommand.detach(current.shape)))
    attached=world.submit_shapes(packet(SphereCommand.attach(current.body_handle,1)))
    assert_equal(attached[0].slot,Int32(2));assert_equal(attached[0].generation,UInt64(2))
    _=world.bodies.submit(body_packet(BodyCommand.remove(current.body_handle)))
    var third=world.bodies.submit(body_packet(BodyCommand.create(replacement_body)))
    assert_equal(third[0].slot,Int32(0));assert_equal(third[0].generation,UInt64(3))
    attached=world.submit_shapes(packet(SphereCommand.attach(third[0],1)))
    assert_equal(attached[0].slot,Int32(2));assert_equal(attached[0].generation,UInt64(3))
    current.shape=ShapeHandle(2,3,owner);current.body_handle=BodyHandle(0,3,owner);expected[1]=current
    shape_reject(world,packet(SphereCommand.reshape(ShapeHandle(0,1,owner),1)),SHAPE_STALE)
    shape_reject(world,packet(SphereCommand.detach(a.shape)),SHAPE_STALE)
    compare_frames(world.detect(),oracle_frame(expected));expect_slot(world,0,2,UInt64.MAX,0)
    world.close()
    print("G03a GPU exhausted-shape orphan retirement, body-generation reuse and no identity resurrection passed")

def main() raises:
    boundary_geometry();completeness_and_offsets();lifecycle_and_invalid();capacity_and_ranges()
    foreign_shape_namespaces();shape_counter_exhaustion();exhausted_shape_orphan_retirement()
    print("G03a actual GPU sphere detection qualification passed; bounded all-pairs prototype; no collision response")
