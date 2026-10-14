"""Actual GPU sphere/OBB geometry: independent six-face oracle and analytic/metamorphic gates."""
from std.collections import List
from std.memory import Pointer
from std.testing import assert_equal,assert_true,assert_raises
from std.math import sqrt
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.lifecycle import BodyCommand,BodyHandle
from experimental.physics_gpu.collision import GpuCollisionWorld,SphereCommand,BoxCommand,ShapeHandle,PairKey,DetectionFrame
from experimental.physics_gpu.shape_kernels import BAD_SHAPE,SHAPE_KIND,SHAPE_WORLD,SHAPE_STALE,SHAPE_FULL,PAIR_OVERFLOW,CONTACT_OVERFLOW,GEOMETRY_RANGE
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import OracleBox,mixed_frame,box_axes,box_center,matrix,apply

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
def compare_frames(actual: DetectionFrame,expected: DetectionFrame) raises:
    assert_equal(len(actual.candidates),len(expected.candidates));assert_equal(len(actual.contacts),len(expected.contacts))
    var previous=Int(-1)
    for i in range(len(actual.candidates)):
        var k=actual.candidates[i];var order=Int(k.a.slot)*64+Int(k.b.slot)
        assert_true(k.a.slot<k.b.slot and order>previous);previous=order;key(k,expected.candidates[i])
    for i in range(len(actual.contacts)):
        var a=actual.contacts[i];var b=expected.contacts[i];key(a.key,b.key)
        near(a.separation,b.separation);vector(a.normal,b.normal);vector(a.witness_a,b.witness_a);vector(a.witness_b,b.witness_b)
        assert_true(abs(a.normal.dot(a.normal)-1)<=1e-12);assert_true(a.separation<=0)
        vector(a.witness_b-a.witness_a,a.normal*a.separation)

def body_packet(c: BodyCommand) -> List[BodyCommand]:
    var p: List[BodyCommand]=[c];return p^
def box_packet(c: BoxCommand) -> List[BoxCommand]:
    var p: List[BoxCommand]=[c];return p^
def sphere_body(p: Vec3) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.sphere(2,.5),position=p)
def fixed_body(p: Vec3=Vec3(0,0,0),q: Quaternion=Quaternion()) raises -> RigidBody3D:
    return RigidBody3D(MassProperties3D.fixed(),position=p,orientation=q)
def add_sphere(mut w: GpuCollisionWorld,p: Vec3,r: Float64) raises -> OracleSphere:
    var b=sphere_body(p);var h=w.bodies.submit(body_packet(BodyCommand.create(b)))
    var c: List[SphereCommand]=[SphereCommand.attach(h[0],r)];var s=w.submit_shapes(c)
    return OracleSphere(s[0],h[0],1,b,r,Vec3(0,0,0))
def add_box(mut w: GpuCollisionWorld,b: RigidBody3D,h: Vec3=Vec3(1,1,1),offset: Vec3=Vec3(0,0,0),q: Quaternion=Quaternion()) raises -> OracleBox:
    var handle=w.bodies.submit(body_packet(BodyCommand.create(b)))
    var shapes=w.submit_boxes(box_packet(BoxCommand.attach(handle[0],h,offset,q)))
    return OracleBox(shapes[0],handle[0],1,b,h,offset,q)

def reject_box(mut w: GpuCollisionWorld,commands: List[BoxCommand],code: Int32) raises:
    var before=w.debug_registry();var bodies=w.bodies.raw();var meta=w.bodies.metadata();var epoch=w._epoch;var returned=False
    with assert_raises():
        _=w.submit_boxes(commands);returned=True
    assert_true(not returned);assert_equal(w.last_error,code);assert_equal(w._epoch,epoch)
    var after=w.debug_registry();var body_after=w.bodies.raw();var meta_after=w.bodies.metadata()
    for i in range(len(before[0])):assert_equal(before[0][i],after[0][i])
    for i in range(len(before[1])):assert_equal(before[1][i],after[1][i])
    for i in range(len(bodies)):assert_equal(bodies[i],body_after[i])
    for i in range(len(meta)):assert_equal(meta[i],meta_after[i])

def analytic_case(p: Vec3,r: Float64,separation: Float64,normal: Vec3,wa: Vec3,wb: Vec3) raises:
    for reversed in range(2):
        var w=GpuCollisionWorld();var spheres=List[OracleSphere]();var boxes=List[OracleBox]()
        if reversed:boxes.append(add_box(w,fixed_body()))
        spheres.append(add_sphere(w,p,r))
        if not reversed:boxes.append(add_box(w,fixed_body()))
        var before=w.bodies.raw();var frame=w.detect();compare_frames(frame,mixed_frame(spheres,boxes))
        assert_equal(len(frame.contacts),1);var hit=frame.contacts[0]
        near(hit.separation,separation);vector(hit.normal,normal*(-1) if reversed else normal)
        vector(hit.witness_a,wb if reversed else wa);vector(hit.witness_b,wa if reversed else wb)
        var after=w.bodies.raw()
        for i in range(len(before)):assert_equal(before[i],after[i])
        w.close()

def analytic_geometry() raises:
    analytic_case(Vec3(2,0,0),1,0,Vec3(-1,0,0),Vec3(1,0,0),Vec3(1,0,0))
    analytic_case(Vec3(1.75,0,0),1,-.25,Vec3(-1,0,0),Vec3(.75,0,0),Vec3(1,0,0))
    analytic_case(Vec3(.2,0,0),.5,-1.3,Vec3(-1,0,0),Vec3(-.3,0,0),Vec3(1,0,0))
    analytic_case(Vec3(-.2,0,0),.5,-1.3,Vec3(1,0,0),Vec3(.3,0,0),Vec3(-1,0,0))
    analytic_case(Vec3(0,0,0),.5,-1.5,Vec3(-1,0,0),Vec3(-.5,0,0),Vec3(1,0,0))
    analytic_case(Vec3(.25,.25,0),.5,-1.25,Vec3(-1,0,0),Vec3(-.25,.25,0),Vec3(1,.25,0))
    analytic_case(Vec3(1,1,1),.5,-.5,Vec3(-1,0,0),Vec3(.5,1,1),Vec3(1,1,1))
    analytic_case(Vec3(4,5,0),5,0,Vec3(-.6,-.8,0),Vec3(1,1,0),Vec3(1,1,0))
    analytic_case(Vec3(3,4,7),7,0,Vec3(-2.0/7,-3.0/7,-6.0/7),Vec3(1,1,1),Vec3(1,1,1))
    for p in [Vec3(2+1e-8,0,0),Vec3(1.8,1.8,0)]:
        var w=GpuCollisionWorld();var spheres: List[OracleSphere]=[add_sphere(w,p,1)];var boxes: List[OracleBox]=[add_box(w,fixed_body())]
        var f=w.detect();compare_frames(f,mixed_frame(spheres,boxes));assert_equal(len(f.contacts),0)
        assert_equal(len(f.candidates),0 if p.x>2 else 1);w.close()
    for size in [1e-6,1e4]:
        var w=GpuCollisionWorld();var spheres: List[OracleSphere]=[add_sphere(w,Vec3(2*size,0,0),size)]
        var boxes: List[OracleBox]=[add_box(w,fixed_body(),Vec3(size,size,size))]
        compare_frames(w.detect(),mixed_frame(spheres,boxes));assert_equal(len(w.detect().contacts),1);w.close()
    print("G03b GPU analytic face/edge/corner tangency, separation, deep/inside overlap, tie rules and reversed pair orientation passed")

def transforms_and_metamorphic() raises:
    var w=GpuCollisionWorld();var q=Quaternion.axis_angle(Vec3(0,1,1),-.4)
    var box=add_box(w,fixed_body(Vec3(7,-4,3),Quaternion.axis_angle(Vec3(1,2,3),.7)),Vec3(1,2,1),Vec3(.3,-.2,.6),q)
    var axes=box_axes(box);var center=box_center(box)
    var sphere=add_sphere(w,center+axes[0]*1.4+axes[1]*.2-axes[2]*.3,.7)
    var spheres: List[OracleSphere]=[sphere];var boxes: List[OracleBox]=[box]
    var first=w.detect();compare_frames(first,mixed_frame(spheres,boxes));assert_equal(len(first.contacts),1)
    near(first.contacts[0].separation,-.3);vector(first.contacts[0].normal,axes[0]) # box has lower slot
    for scale in [-1.0,7.0]:
        var rescaled=Quaternion(q.x*scale,q.y*scale,q.z*scale,q.w*scale)
        _=w.submit_boxes(box_packet(BoxCommand.reshape(box.shape,box.half_extents,box.offset,rescaled)))
        box.orientation=rescaled;box.revision+=1;boxes[0]=box
        var frame=w.detect();compare_frames(frame,mixed_frame(spheres,boxes))
        vector(frame.contacts[0].normal,first.contacts[0].normal);near(frame.contacts[0].separation,first.contacts[0].separation)
        vector(frame.contacts[0].witness_a,first.contacts[0].witness_a);vector(frame.contacts[0].witness_b,first.contacts[0].witness_b)
    var before=w.detect();var rotation=Quaternion(0,0,sqrt(.5),sqrt(.5));var transform=matrix(rotation);var translation=Vec3(20,-10,5)
    box.body.position=apply(transform,box.body.position)+translation;box.body.orientation=rotation*box.body.orientation
    sphere.body.position=apply(transform,sphere.body.position)+translation;sphere.body.orientation=rotation*sphere.body.orientation
    _=w.bodies.submit(body_packet(BodyCommand.update(box.body_handle,box.body)))
    _=w.bodies.submit(body_packet(BodyCommand.update(sphere.body_handle,sphere.body)))
    boxes[0]=box;spheres[0]=sphere
    var moved=w.detect();compare_frames(moved,mixed_frame(spheres,boxes))
    vector(moved.contacts[0].normal,apply(transform,before.contacts[0].normal))
    vector(moved.contacts[0].witness_a,apply(transform,before.contacts[0].witness_a)+translation)
    vector(moved.contacts[0].witness_b,apply(transform,before.contacts[0].witness_b)+translation)
    near(moved.contacts[0].separation,before.contacts[0].separation);w.close()
    print("G03b GPU composed body/local rotations, corner-enumerated AABBs, quaternion sign/scale and rigid-transform invariance passed")

def rotated_features() raises:
    var q=Quaternion.axis_angle(Vec3(0,1,1),-.4)
    var outer=Quaternion.axis_angle(Vec3(1,2,3),.7)
    for feature in range(4):
        var w=GpuCollisionWorld();var box=add_box(w,fixed_body(Vec3(7,-4,3),outer),Vec3(1,2,3),Vec3(.3,-.2,.6),q)
        var axes=box_axes(box);var origin=box_center(box)
        var u=Vec3(1.4,.2,-.3) if feature==0 else Vec3(1.3,2.4,.2) if feature==1 else Vec3(1.2,2.3,3.6) if feature==2 else Vec3(.2,0,0)
        var sphere=add_sphere(w,origin+axes[0]*u.x+axes[1]*u.y+axes[2]*u.z,1)
        var spheres: List[OracleSphere]=[sphere];var boxes: List[OracleBox]=[box]
        var frame=w.detect();compare_frames(frame,mixed_frame(spheres,boxes));assert_equal(len(frame.contacts),1)
        var expected_normal=axes[0] if feature==0 or feature==3 else axes[0]*.6+axes[1]*.8 if feature==1 else axes[0]*(2.0/7)+axes[1]*(3.0/7)+axes[2]*(6.0/7)
        var expected_separation=Float64(-.6 if feature==0 else -.5 if feature==1 else -.3 if feature==2 else -1.8)
        vector(frame.contacts[0].normal,expected_normal);near(frame.contacts[0].separation,expected_separation)
        w.close()
    print("G03b GPU independently transformed face/edge/corner and inside-box analytic normals/separations passed")

def dynamic_box_trajectory() raises:
    var w=GpuCollisionWorld()
    var body=RigidBody3D(MassProperties3D.box(2,Vec3(1,2,3)),position=Vec3(2,3,-1),orientation=Quaternion.axis_angle(Vec3(1,2,3),.2))
    body.angular_velocity=Vec3(.2,.1,-.15);body.linear_velocity=Vec3(.1,-.05,.02)
    var box=add_box(w,body,Vec3(1,2,3),Vec3(.3,-.2,.6),Quaternion.axis_angle(Vec3(0,1,1),.35))
    var axes=box_axes(box);var sphere=add_sphere(w,box_center(box)+axes[0]*1.3+axes[1]*.3+axes[2]*.2,.8)
    var boxes: List[OracleBox]=[box];var spheres: List[OracleSphere]=[sphere];var storage=w.bodies.storage_ids()
    compare_frames(w.detect(),mixed_frame(spheres,boxes))
    for _ in range(4):
        assert_equal(w.bodies.step(1.0/60,Vec3(0,0,0)),0)
        _=boxes[0].body.integrate(1.0/60,Vec3(0,0,0));_=spheres[0].body.integrate(1.0/60,Vec3(0,0,0))
        var frame=w.detect();compare_frames(frame,mixed_frame(spheres,boxes));assert_equal(len(frame.contacts),1)
    var after=w.bodies.storage_ids();assert_equal(storage[0],after[0]);assert_equal(storage[1],after[1])
    w.close();print("G03b GPU rotating dynamic-box/local-offset trajectory and contact geometry versus CPU integration/oracle passed")

def lifecycle_and_invalid() raises:
    var w=GpuCollisionWorld();var box=add_box(w,fixed_body());var sphere=add_sphere(w,Vec3(1.5,0,0),1)
    var spheres: List[OracleSphere]=[sphere];var boxes: List[OracleBox]=[box]
    var published=w.detect();compare_frames(published,mixed_frame(spheres,boxes))
    var other=GpuCollisionWorld();var foreign=add_box(other,fixed_body())
    reject_box(w,box_packet(BoxCommand.detach(foreign.shape)),SHAPE_WORLD)
    var wrong=BoxCommand.reshape(box.shape,Vec3(1,1,1));wrong.half_extents.x=0
    reject_box(w,box_packet(wrong),BAD_SHAPE)
    var bad_q=BoxCommand.reshape(box.shape,Vec3(1,1,1));bad_q.local_orientation=Quaternion(0,0,0,0)
    var mixed: List[BoxCommand]=[BoxCommand.reshape(box.shape,Vec3(.8,.8,.8)),bad_q]
    reject_box(w,mixed,BAD_SHAPE);assert_equal(w.last_bad_command,Int32(1))
    var huge=Float64(1e308);var inf=huge*huge
    for value in [Float64(-1),Float64(0),Float64(1e-7),Float64(1e4+1),inf,inf-inf]:
        wrong=BoxCommand.reshape(box.shape,Vec3(1,1,1));wrong.half_extents.y=value
        reject_box(w,box_packet(wrong),BAD_SHAPE)
    for q in [Quaternion(0,0,0,0),Quaternion(inf,0,0,1),Quaternion(inf-inf,0,0,1),Quaternion(0,0,0,1e-13),Quaternion(0,0,0,1e13)]:
        wrong=BoxCommand.reshape(box.shape,Vec3(1,1,1));wrong.local_orientation=q
        reject_box(w,box_packet(wrong),BAD_SHAPE)
        with assert_raises():_=BoxCommand.attach(box.body_handle,Vec3(1,1,1),orientation=q)
    for center in [inf,inf-inf,Float64(1e6+1)]:
        wrong=BoxCommand.reshape(box.shape,Vec3(1,1,1));wrong.local_center.x=center
        reject_box(w,box_packet(wrong),BAD_SHAPE)
    reject_box(w,box_packet(BoxCommand.reshape(sphere.shape,Vec3(1,1,1))),SHAPE_KIND)
    var change_kind: List[SphereCommand]=[SphereCommand.reshape(box.shape,1)]
    var snapshot=w.debug_registry()
    with assert_raises():_=w.submit_shapes(change_kind)
    assert_equal(w.last_error,SHAPE_KIND);var after=w.debug_registry()
    for i in range(len(snapshot[0])):assert_equal(snapshot[0][i],after[0][i])
    for i in range(len(snapshot[1])):assert_equal(snapshot[1][i],after[1][i])
    compare_frames(w.detect(),mixed_frame(spheres,boxes));compare_frames(published,mixed_frame(spheres,boxes))
    _=w.bodies.submit(body_packet(BodyCommand.remove(box.body_handle)))
    var replacement=w.bodies.submit(body_packet(BodyCommand.create(fixed_body())))
    assert_equal(replacement[0].slot,box.body_handle.slot);assert_equal(replacement[0].generation,UInt64(2))
    var attached=w.submit_boxes(box_packet(BoxCommand.attach(replacement[0],Vec3(1,1,1))))
    assert_equal(attached[0].slot,box.shape.slot);assert_equal(attached[0].generation,UInt64(2))
    reject_box(w,box_packet(BoxCommand.reshape(box.shape,Vec3(1,1,1))),SHAPE_STALE)
    box.shape=ShapeHandle(0,2,box.shape.owner);box.body_handle=BodyHandle(0,2,box.body_handle.owner);boxes[0]=box
    compare_frames(w.detect(),mixed_frame(spheres,boxes))
    _=w.submit_boxes(box_packet(BoxCommand.detach(box.shape)))
    var cleared=w.debug_registry();assert_equal(cleared[0][1],UInt64(0));assert_equal(cleared[0][67],UInt64(3))
    for field in range(11):
        assert_equal(cleared[1][field*66+1],Float64(-987654321.25))
        assert_equal(cleared[1][field*66],Float64(-987654321.25));assert_equal(cleared[1][field*66+65],Float64(-987654321.25))
    attached=w.submit_boxes(box_packet(BoxCommand.attach(box.body_handle,Vec3(1,1,1))))
    assert_equal(attached[0].slot,Int32(0));assert_equal(attached[0].generation,UInt64(3))
    reject_box(w,box_packet(BoxCommand.detach(box.shape)),SHAPE_STALE)
    box.shape=ShapeHandle(0,3,box.shape.owner);boxes[0]=box
    compare_frames(w.detect(),mixed_frame(spheres,boxes))
    w.close();other.close()
    print("G03b GPU box lifecycle/revisions, foreign/stale handles, kind immutability, raw nonfinite/degenerate rejection and full transaction rollback passed")

def capacity_and_overflow() raises:
    var w=GpuCollisionWorld(2016,2016);var spheres=List[OracleSphere]();var boxes=List[OracleBox]()
    for _ in range(32):boxes.append(add_box(w,fixed_body()))
    for _ in range(32):spheres.append(add_sphere(w,Vec3(0,0,0),1))
    var full=w.detect();compare_frames(full,mixed_frame(spheres,boxes));assert_equal(len(full.candidates),1520);assert_equal(len(full.contacts),1520)
    var extra=w.bodies.submit(body_packet(BodyCommand.create(fixed_body())))
    reject_box(w,box_packet(BoxCommand.attach(extra[0],Vec3(1,1,1))),SHAPE_FULL);w.close()
    for mode in range(2):
        var limited=GpuCollisionWorld(Int32(0 if mode==0 else 10),Int32(0 if mode==1 else 10))
        _=add_box(limited,fixed_body());_=add_sphere(limited,Vec3(0,0,0),1)
        var state=limited.bodies.raw();var epoch=limited._epoch
        with assert_raises():_=limited.detect()
        assert_equal(limited.last_error,PAIR_OVERFLOW if mode==0 else CONTACT_OVERFLOW);assert_equal(limited._epoch,epoch)
        var after=limited.bodies.raw()
        for i in range(len(state)):assert_equal(state[i],after[i])
        limited.close()
    var unsupported=GpuCollisionWorld();_=add_box(unsupported,fixed_body());_=add_box(unsupported,fixed_body())
    assert_equal(len(unsupported.detect().candidates),0);assert_equal(len(unsupported.detect().contacts),0);unsupported.close()
    var range_world=GpuCollisionWorld();_=add_box(range_world,fixed_body(Vec3(1e9+1,0,0)))
    with assert_raises():_=range_world.detect()
    assert_equal(range_world.last_error,GEOMETRY_RANGE);range_world.close()
    print("G03b GPU 64 mixed shapes/1520 supported pairs, box/box exclusion, explicit overflow and center-range failure passed")

def main() raises:
    analytic_geometry();transforms_and_metamorphic();rotated_features();dynamic_box_trajectory();lifecycle_and_invalid();capacity_and_overflow()
    print("G03b actual GPU sphere/OBB detection qualification passed; sphere/sphere retained; no plane, box/box or response")
