"""Finite detection-only geometry edits, not a simulated box stack."""
from std.testing import assert_equal
from mojo_game import RigidBody3D,MassProperties3D,Vec3,Quaternion
from experimental.physics_gpu.box_box import GpuBoxBoxDetection
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.collision import BoxCommand

def show(mut w: GpuBoxBoxDetection,label: String,pairs: Int,points: Int,epoch: UInt64) raises:
    var before=w.world.bodies.raw();var frame=w.detect();assert_equal(len(frame.patches),pairs);assert_equal(frame.epoch,epoch)
    var total=0
    for i in range(len(frame.patches)):total+=len(frame.patches[i].points)
    assert_equal(total,points);var after=w.world.bodies.raw()
    for i in range(len(before)):assert_equal(before[i],after[i])
    print("box_box_diagnostic",label,"epoch",frame.epoch,"patches",len(frame.patches),"points",total,"legacy_contacts",len(frame.legacy.contacts))

def main() raises:
    var w=GpuBoxBoxDetection();var q=Quaternion.axis_angle(Vec3(0,0,1),.3)
    var a=RigidBody3D(MassProperties3D.fixed());var b=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,0,.4),orientation=q)
    var handles=w.world.bodies.submit([BodyCommand.create(a),BodyCommand.create(b)]);var shapes=w.world.submit_boxes([BoxCommand.attach(handles[0],Vec3(1,1,.25)),BoxCommand.attach(handles[1],Vec3(1,1,.25))])
    show(w,"rotated_overlap",1,8,1)
    b.position=Vec3(0,0,.5);_=w.world.bodies.submit([BodyCommand.update(handles[1],b)]);show(w,"touch",1,8,2)
    b.position=Vec3(0,0,.6);_=w.world.bodies.submit([BodyCommand.update(handles[1],b)]);show(w,"separated",0,0,3)
    b.position=Vec3(0,0,.4);_=w.world.bodies.submit([BodyCommand.update(handles[1],b)]);_=w.world.submit_boxes([BoxCommand.reshape(shapes[1],Vec3(.4,.4,.25))]);show(w,"reshaped",1,4,4)
    _=w.world.bodies.submit([BodyCommand.remove(handles[1])]);show(w,"removed",0,0,5)
    var replacement=w.world.bodies.submit([BodyCommand.create(b)]);assert_equal(replacement[0].generation,handles[1].generation+1);_=w.world.submit_boxes([BoxCommand.attach(replacement[0],Vec3(.4,.4,.25))]);show(w,"slot_reused",1,4,6)
    w.close();print("Detection-only actual GPU diagnostic passed; explicit pose edits, no response/integration/history/sleep adoption")
