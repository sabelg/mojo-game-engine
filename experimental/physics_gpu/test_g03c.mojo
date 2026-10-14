"""Actual GPU one-point history: independent reference and explicit analytic sequences."""
from std.collections import List
from std.memory import Pointer
from std.math import sin,cos
from std.testing import assert_equal,assert_true,assert_raises
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.collision import SphereCommand,BoxCommand,ShapeHandle,PairKey
from experimental.physics_gpu.contact_history import GpuContactHistory,TrackedContact,ContactFrame
from experimental.physics_gpu.contact_reference import ContactReference
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.history_kernels import HISTORY_FULL,EVENTS_FULL,ID_FULL,AGE_FULL,EPOCH_FULL

def near(a: Float64,b: Float64) raises:
    assert_true(abs(a-b)<=1e-9+1e-12*abs(b))
def vector(a: Vec3,b: Vec3) raises:
    near(a.x,b.x);near(a.y,b.y);near(a.z,b.z)
def key(a: PairKey,b: PairKey) raises:
    assert_equal(a.a.slot,b.a.slot);assert_equal(a.b.slot,b.b.slot)
    assert_equal(a.a.generation,b.a.generation);assert_equal(a.b.generation,b.b.generation)
    assert_equal(a.a.owner,b.a.owner);assert_equal(a.b.owner,b.b.owner)
    assert_equal(a.revision_a,b.revision_a);assert_equal(a.revision_b,b.revision_b)
    assert_equal(a.body_a.slot,b.body_a.slot);assert_equal(a.body_b.slot,b.body_b.slot)
    assert_equal(a.body_a.generation,b.body_a.generation);assert_equal(a.body_b.generation,b.body_b.generation)
def record(a: TrackedContact,b: TrackedContact) raises:
    key(a.contact.key,b.contact.key);assert_equal(a.identity,b.identity);assert_equal(a.age,b.age)
    assert_equal(a.feature,b.feature);assert_equal(a.ambiguous,b.ambiguous);assert_equal(a.status,b.status)
    vector(a.contact.normal,b.contact.normal);near(a.contact.separation,b.contact.separation)
    vector(a.contact.witness_a,b.contact.witness_a);vector(a.contact.witness_b,b.contact.witness_b)
    assert_true(abs(a.contact.normal.dot(a.contact.normal)-1)<=1e-12)
    vector(a.contact.witness_b-a.contact.witness_a,a.contact.normal*a.contact.separation)
def compare(a: ContactFrame,b: ContactFrame) raises:
    assert_equal(a.epoch,b.epoch);assert_equal(len(a.active),len(b.active));assert_equal(len(a.ended),len(b.ended))
    var previous=Int(-1)
    for i in range(len(a.active)):
        record(a.active[i],b.active[i]);var k=a.active[i].contact.key;var order=Int(k.a.slot)*64+Int(k.b.slot)
        assert_true(k.a.slot<k.b.slot and order>previous);previous=order
    previous=-1
    for i in range(len(a.ended)):
        record(a.ended[i],b.ended[i]);var k=a.ended[i].contact.key;var order=Int(k.a.slot)*64+Int(k.b.slot)
        assert_true(k.a.slot<k.b.slot and order>previous);previous=order
def tick(mut h: GpuContactHistory,mut reference: ContactReference,spheres: List[OracleSphere],boxes: List[OracleBox]) raises -> ContactFrame:
    var actual=h.update();var expected=reference.update(spheres,boxes);compare(actual,expected);return actual^
def fixed() raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.fixed())
def dynamic(p: Vec3) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.sphere(2,.5),position=p)
def add_sphere(mut h: GpuContactHistory,p: Vec3,r: Float64=1) raises -> OracleSphere:
    var b=dynamic(p);var bodies=h.world.bodies.submit([BodyCommand.create(b)])
    var shapes=h.world.submit_shapes([SphereCommand.attach(bodies[0],r)])
    return OracleSphere(shapes[0],bodies[0],1,b,r,Vec3(0,0,0))
def add_box(mut h: GpuContactHistory,half: Vec3=Vec3(1,2,3)) raises -> OracleBox:
    var b=fixed();var bodies=h.world.bodies.submit([BodyCommand.create(b)])
    var shapes=h.world.submit_boxes([BoxCommand.attach(bodies[0],half)])
    return OracleBox(shapes[0],bodies[0],1,b,half,Vec3(0,0,0),Quaternion())
def move_sphere(mut h: GpuContactHistory,mut s: OracleSphere,p: Vec3) raises:
    s.body.position=p;_=h.world.bodies.submit([BodyCommand.update(s.body_handle,s.body)])
def counts(f: ContactFrame,identity: UInt64,age: UInt64,status: UInt64,feature: UInt64,ended: Int=0) raises:
    assert_equal(len(f.active),1);assert_equal(len(f.ended),ended)
    assert_equal(f.active[0].identity,identity);assert_equal(f.active[0].age,age);assert_equal(f.active[0].status,status);assert_equal(f.active[0].feature,feature)

def continuity_and_recontact() raises:
    var h=GpuContactHistory();var reference=ContactReference();var spheres: List[OracleSphere]=[add_sphere(h,Vec3(0,0,0)),add_sphere(h,Vec3(1.5,0,0))];var boxes=List[OracleBox]()
    var initial=tick(h,reference,spheres,boxes);counts(initial,1,1,1,0)
    move_sphere(h,spheres[1],Vec3(1.4,.1,0));counts(tick(h,reference,spheres,boxes),1,2,2,0)
    spheres[1].body.linear_velocity=Vec3(.01,0,0)
    _=h.world.bodies.submit([BodyCommand.update(spheres[1].body_handle,spheres[1].body)])
    var storage=h.world.bodies.storage_ids()
    for frame in range(4):
        assert_equal(h.world.bodies.step(1.0/60,Vec3(0,0,0)),0)
        for i in range(2):_=spheres[i].body.integrate(1.0/60,Vec3(0,0,0))
        counts(tick(h,reference,spheres,boxes),1,UInt64(frame+3),2,0)
    move_sphere(h,spheres[1],Vec3(4,0,0));var separated=tick(h,reference,spheres,boxes)
    assert_equal(len(separated.active),0);assert_equal(len(separated.ended),1);assert_equal(separated.ended[0].identity,UInt64(1));assert_equal(separated.ended[0].age,UInt64(6))
    var empty=tick(h,reference,spheres,boxes);assert_equal(len(empty.active),0);assert_equal(len(empty.ended),0)
    move_sphere(h,spheres[1],Vec3(1.5,0,0));counts(tick(h,reference,spheres,boxes),2,1,1,0)
    counts(initial,1,1,1,0) # previously returned observation remains a value copy
    var after=h.world.bodies.storage_ids();assert_equal(storage[0],after[0]);assert_equal(storage[1],after[1])
    h.close()
    with assert_raises():_=h.update()
    print("G03c GPU lifetime/age continuity, live integration, separation/empty/recontact and immutable observations passed")

def features_reshape_and_ambiguity() raises:
    var h=GpuContactHistory();var reference=ContactReference();var boxes: List[OracleBox]=[add_box(h)];var spheres: List[OracleSphere]=[add_sphere(h,Vec3(1.4,.2,.1))]
    counts(tick(h,reference,spheres,boxes),1,1,1,32)
    move_sphere(h,spheres[0],Vec3(1.3,2.4,.1));counts(tick(h,reference,spheres,boxes),2,1,1,35,1)
    move_sphere(h,spheres[0],Vec3(1.2,2.3,3.6));counts(tick(h,reference,spheres,boxes),3,1,1,36,1)
    move_sphere(h,spheres[0],Vec3(.2,.1,.1));counts(tick(h,reference,spheres,boxes),4,1,1,50,1)
    move_sphere(h,spheres[0],Vec3(.3,.2,.2));counts(tick(h,reference,spheres,boxes),4,2,2,50)
    _=h.world.submit_boxes([BoxCommand.reshape(boxes[0].shape,boxes[0].half_extents)]);boxes[0].revision=2
    counts(tick(h,reference,spheres,boxes),5,1,1,50,1)
    _=h.world.submit_shapes([SphereCommand.reshape(spheres[0].shape,.9)]);spheres[0].radius=.9;spheres[0].revision=2
    counts(tick(h,reference,spheres,boxes),6,1,1,50,1)
    move_sphere(h,spheres[0],Vec3(0,0,0));var ambiguous=tick(h,reference,spheres,boxes);counts(ambiguous,7,1,1,50,1);assert_true(ambiguous.active[0].ambiguous)
    ambiguous=tick(h,reference,spheres,boxes);counts(ambiguous,8,1,1,50,1);assert_true(ambiguous.active[0].ambiguous)
    move_sphere(h,spheres[0],Vec3(.1,0,0));counts(tick(h,reference,spheres,boxes),9,1,1,50,1)
    counts(tick(h,reference,spheres,boxes),9,2,2,50)
    _=h.world.submit_boxes([BoxCommand.reshape(boxes[0].shape,Vec3(1,1,1))]);boxes[0].half_extents=Vec3(1,1,1);boxes[0].revision=3
    move_sphere(h,spheres[0],Vec3(.2,.2,0));ambiguous=tick(h,reference,spheres,boxes);counts(ambiguous,10,1,1,50,1);assert_true(ambiguous.active[0].ambiguous)
    h.close()
    var coincident=GpuContactHistory();var cr=ContactReference();var cs: List[OracleSphere]=[add_sphere(coincident,Vec3(0,0,0)),add_sphere(coincident,Vec3(0,0,0))];var none=List[OracleBox]()
    counts(tick(coincident,cr,cs,none),1,1,1,1);counts(tick(coincident,cr,cs,none),2,1,1,1,1)
    move_sphere(coincident,cs[1],Vec3(.1,0,0));counts(tick(coincident,cr,cs,none),3,1,1,0,1);counts(tick(coincident,cr,cs,none),3,2,2,0);coincident.close()
    var normal=GpuContactHistory();var nr=ContactReference();var ns: List[OracleSphere]=[add_sphere(normal,Vec3(0,0,0)),add_sphere(normal,Vec3(1.5,0,0))]
    counts(tick(normal,nr,ns,none),1,1,1,0)
    move_sphere(normal,ns[1],Vec3(1.5*cos(.1),1.5*sin(.1),0));counts(tick(normal,nr,ns,none),1,2,2,0)
    move_sphere(normal,ns[1],Vec3(1.5*cos(.8),1.5*sin(.8),0));counts(tick(normal,nr,ns,none),2,1,1,0,1);normal.close()
    print("G03c GPU face/edge/corner/inside feature resets, reshape revisions, ambiguity and normal-continuity gate passed")

def lifecycle_invalidation() raises:
    var h=GpuContactHistory();var reference=ContactReference();var boxes: List[OracleBox]=[add_box(h)];var spheres: List[OracleSphere]=[add_sphere(h,Vec3(1.5,0,0))]
    counts(tick(h,reference,spheres,boxes),1,1,1,32)
    var old=boxes[0].shape;_=h.world.submit_boxes([BoxCommand.detach(old)])
    var replacement=h.world.submit_boxes([BoxCommand.attach(boxes[0].body_handle,boxes[0].half_extents)])
    assert_equal(replacement[0].slot,Int32(0));assert_equal(replacement[0].generation,UInt64(2));boxes[0].shape=ShapeHandle(0,2,old.owner)
    counts(tick(h,reference,spheres,boxes),2,1,1,32,1)
    _=h.world.bodies.submit([BodyCommand.remove(boxes[0].body_handle),BodyCommand.create(fixed())])
    boxes[0].body_handle=BodyHandle(0,2,old.owner)
    replacement=h.world.submit_boxes([BoxCommand.attach(boxes[0].body_handle,boxes[0].half_extents)])
    assert_equal(replacement[0].slot,Int32(0));assert_equal(replacement[0].generation,UInt64(3));boxes[0].shape=ShapeHandle(0,3,old.owner)
    counts(tick(h,reference,spheres,boxes),3,1,1,32,1)
    _=h.world.bodies.submit([BodyCommand.remove(spheres[0].body_handle)])
    var no_spheres=List[OracleSphere]();var removed=tick(h,reference,no_spheres,boxes)
    assert_equal(len(removed.active),0);assert_equal(len(removed.ended),1);assert_equal(removed.ended[0].identity,UInt64(3))
    var body=spheres[0].body;var created=h.world.bodies.submit([BodyCommand.create(body)]);spheres[0].body_handle=created[0]
    assert_equal(created[0].slot,Int32(1));assert_equal(created[0].generation,UInt64(2))
    var attached=h.world.submit_shapes([SphereCommand.attach(created[0],1)]);assert_equal(attached[0].slot,Int32(1));assert_equal(attached[0].generation,UInt64(2));spheres[0].shape=attached[0]
    counts(tick(h,reference,spheres,boxes),4,1,1,32)
    var cache=h.debug_cache();var foreign=GpuContactHistory();var foreign_box=add_box(foreign)
    with assert_raises():_=h.world.submit_boxes([BoxCommand.reshape(foreign_box.shape,Vec3(1,2,3))])
    assert_equal(h.world.last_error,Int32(38));foreign.close()
    var bad=BoxCommand.reshape(boxes[0].shape,Vec3(1,2,3));bad.local_orientation=Quaternion(0,0,0,0)
    with assert_raises():_=h.world.submit_boxes([BoxCommand.reshape(boxes[0].shape,Vec3(.8,.8,.8)),bad])
    var after=h.debug_cache()
    for i in range(len(cache[0])):assert_equal(cache[0][i],after[0][i])
    for i in range(len(cache[1])):assert_equal(cache[1][i],after[1][i])
    for i in range(5):assert_equal(cache[2][i],after[2][i])
    counts(tick(h,reference,spheres,boxes),4,2,2,32)
    with assert_raises():_=h.world.submit_boxes([BoxCommand.reshape(old,Vec3(1,2,3))])
    counts(tick(h,reference,spheres,boxes),4,3,2,32)
    h.close();print("G03c GPU shape/body removal and slot reuse cannot carry stale lifetime state; rejected commands preserve history passed")

def rejected_update(mut h: GpuContactHistory,code: Int32,geometry_error: Bool=False) raises:
    var before=h.debug_cache();var bodies=h.world.bodies.raw();var returned=False
    with assert_raises():
        _=h.update();returned=True
    assert_true(not returned);assert_equal(h.last_error,code)
    if geometry_error:assert_equal(h.world.last_error,code)
    var after=h.debug_cache();var body_after=h.world.bodies.raw()
    for i in range(len(before[0])):assert_equal(before[0][i],after[0][i])
    for i in range(len(before[1])):assert_equal(before[1][i],after[1][i])
    for i in range(5):assert_equal(before[2][i],after[2][i])
    for i in range(len(bodies)):assert_equal(bodies[i],body_after[i])

# Finite test-only counter setup; no production reset/mutation API is added.
def seed_counters(state: Pointer[UInt64,MutAnyOrigin],cache: Pointer[UInt64,MutAnyOrigin],epoch: UInt64,next_id: UInt64,age: UInt64):
    state[unsafe_offset=2]=epoch;state[unsafe_offset=3]=next_id
    if age!=0:cache[unsafe_offset=13]=age

def capacity_and_transaction() raises:
    var zero=GpuContactHistory(256,256,0,0);_=add_sphere(zero,Vec3(0,0,0));_=add_sphere(zero,Vec3(1.5,0,0));rejected_update(zero,HISTORY_FULL);zero.close()
    var h=GpuContactHistory(256,256,256,1);var reference=ContactReference(256,1);var boxes: List[OracleBox]=[add_box(h)];var spheres: List[OracleSphere]=[add_sphere(h,Vec3(1.4,.2,.1))]
    counts(tick(h,reference,spheres,boxes),1,1,1,32)
    move_sphere(h,spheres[0],Vec3(.2,.1,.1));rejected_update(h,EVENTS_FULL)
    with assert_raises():_=reference.update(spheres,boxes)
    assert_equal(reference.epoch,UInt64(1));assert_equal(reference.next_id,UInt64(2))
    move_sphere(h,spheres[0],Vec3(1.4,.2,.1));counts(tick(h,reference,spheres,boxes),1,2,2,32)
    assert_equal(h.debug_cache()[2][3],UInt64(2));h.close()
    var geometry=GpuContactHistory(0,256);_=add_sphere(geometry,Vec3(0,0,0));_=add_sphere(geometry,Vec3(1.5,0,0));rejected_update(geometry,40,True);geometry.close()
    var dense=GpuContactHistory(2016,2016,2016,4032);var dr=ContactReference(2016,4032);var ds=List[OracleSphere]();var none=List[OracleBox]()
    for _ in range(64):ds.append(add_sphere(dense,Vec3(0,0,0)))
    var first=tick(dense,dr,ds,none);assert_equal(len(first.active),2016);assert_equal(len(first.ended),0)
    var second=tick(dense,dr,ds,none);assert_equal(len(second.active),2016);assert_equal(len(second.ended),2016)
    for i in range(2016):
        assert_equal(first.active[i].identity,UInt64(i+1));assert_equal(second.active[i].identity,UInt64(2017+i));assert_equal(second.active[i].age,UInt64(1));assert_equal(second.ended[i].identity,UInt64(i+1))
    var raw=dense.debug_cache();assert_equal(raw[0][0],UInt64.MAX);assert_equal(raw[0][len(raw[0])-1],UInt64.MAX)
    assert_equal(raw[1][0],Float64(-987654321.25));assert_equal(raw[1][len(raw[1])-1],Float64(-987654321.25));dense.close()
    print("G03c GPU history/event overflow atomic rollback, geometry failure, deterministic 2016 contacts/4032 events and guards passed")

def exhaustion() raises:
    var h=GpuContactHistory();var reference=ContactReference();var spheres: List[OracleSphere]=[add_sphere(h,Vec3(0,0,0)),add_sphere(h,Vec3(1.5,0,0))];var none=List[OracleBox]()
    h.world.bodies._ctx.enqueue_function[seed_counters](h._state,h._current,UInt64(0),UInt64.MAX,UInt64(0),grid_dim=1,block_dim=1);h.world.bodies._ctx.synchronize();reference.next_id=UInt64.MAX
    counts(tick(h,reference,spheres,none),UInt64.MAX,1,1,0);counts(tick(h,reference,spheres,none),UInt64.MAX,2,2,0)
    move_sphere(h,spheres[1],Vec3(4,0,0));var ended=tick(h,reference,spheres,none);assert_equal(ended.ended[0].identity,UInt64.MAX)
    move_sphere(h,spheres[1],Vec3(1.5,0,0));rejected_update(h,ID_FULL)
    with assert_raises():_=reference.update(spheres,none)
    assert_equal(h.debug_cache()[2][3],UInt64(0));h.close()
    for mode in range(2):
        var limited=GpuContactHistory();var r=ContactReference();var s: List[OracleSphere]=[add_sphere(limited,Vec3(0,0,0)),add_sphere(limited,Vec3(1.5,0,0))]
        _=tick(limited,r,s,none)
        limited.world.bodies._ctx.enqueue_function[seed_counters](limited._state,limited._current,UInt64.MAX if mode==0 else UInt64(1),UInt64(2),UInt64.MAX if mode==1 else UInt64(0),grid_dim=1,block_dim=1)
        limited.world.bodies._ctx.synchronize();rejected_update(limited,EPOCH_FULL if mode==0 else AGE_FULL)
        if mode==0:r.epoch=UInt64.MAX
        else:r.previous[0].age=UInt64.MAX
        with assert_raises():_=r.update(s,none)
        limited.close()
    print("G03c GPU lifetime-ID/age/epoch exhaustion rejects without wrap or stale resurrection passed")

def main() raises:
    continuity_and_recontact();features_reshape_and_ambiguity();lifecycle_invalidation();capacity_and_transaction();exhaustion()
    print("G03c actual GPU one-point persistent contact history qualified; no manifold solver or impulse reuse")
