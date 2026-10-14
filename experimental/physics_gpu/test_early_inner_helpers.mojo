from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from .early_inner_response import GpuEarlyInnerBoxResponse
from .box_oracle import OracleBox
from .lifecycle import BodyCommand
from .collision import BoxCommand

def add_box_early_inner(mut response: GpuEarlyInnerBoxResponse,p: Vec3,half: Vec3=Vec3(.5,.5,.5),mass: Float64=2,v: Vec3=Vec3(0,0,0),omega: Vec3=Vec3(0,0,0),orientation: Quaternion=Quaternion()) raises -> OracleBox:
    var body=RigidBody3D(MassProperties3D.fixed() if mass==0 else MassProperties3D.box(mass,half*2),position=p,orientation=orientation);body.linear_velocity=v;body.angular_velocity=omega
    var handles=response.detection.world.bodies.submit([BodyCommand.create(body)]);var shapes=response.detection.world.submit_boxes([BoxCommand.attach(handles[0],half)])
    return OracleBox(shapes[0],handles[0],1,body,half,Vec3(0,0,0),Quaternion())

