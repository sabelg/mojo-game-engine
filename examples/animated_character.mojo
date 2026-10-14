"""Native two-joint character example: clip blending and GPU skinning."""
from std.math import sin
from std.sys import argv
from mojo_game import Graphics3D,Mesh,Vec3,Vec2,Transform3D,Mat4,Quaternion,Skeleton,Joint,SkinnedMesh,AnimationClip,PoseTrack,PoseKey,blend_pose,Material

def main() raises:
    var args=argv()
    var smoke=len(args)>1 and args[1]=="--smoke"
    var device=Graphics3D("Atlas | Skeletal character",960,600,smoke)
    var skeleton=Skeleton()
    skeleton.joints.append(Joint(-1,Transform3D(),Mat4()))
    var arm_bind=Transform3D(Vec3(.6,1.4,0))
    skeleton.joints.append(Joint(0,arm_bind,arm_bind.matrix().inverse()))
    var mesh=Mesh()
    var influences=List[Int]()
    var cube=Mesh.cube()
    var parts: List[Transform3D]=[Transform3D(Vec3(0,.8,0),scale=Vec3(.8,1.6,.5)),Transform3D(Vec3(1.1,1.4,0),scale=Vec3(1,.25,.25))]
    for part in range(2):
        for i in range(len(cube.vertices)//8):
            var offset=i*8
            var p=parts[part].matrix().point(Vec3(Float64(cube.vertices[offset]),Float64(cube.vertices[offset+1]),Float64(cube.vertices[offset+2])))
            var n=Vec3(Float64(cube.vertices[offset+3]),Float64(cube.vertices[offset+4]),Float64(cube.vertices[offset+5]))
            _=mesh.vertex(p,n,Vec2(Float64(cube.vertices[offset+6]),Float64(cube.vertices[offset+7])))
            influences.append(part)
        for index in cube.indices:mesh.indices.append(index+UInt32(part*len(cube.vertices)//8))
    var skin=SkinnedMesh(mesh^)
    for joint in influences:
        for i in range(4):
            skin.joints.append(joint)
            skin.weights.append(1.0 if i==0 else 0.0)
    var wave=AnimationClip()
    var track=PoseTrack(1,1)
    for i in range(5):
        var q=Quaternion.axis_angle(Vec3(0,0,1),sin(Float64(i)*1.57079632679)*1.2)
        track.keys.append(PoseKey(Float64(i)*.5,q.x,q.y,q.z,q.w))
    wave.tracks.append(track^)
    wave.duration=2
    var rest=AnimationClip()
    var handle=skin.upload(device)
    var frame=0
    var seconds: Float64=0
    var camera=Mat4.perspective(1,960.0/600,.1,100)*Mat4.look_at(Vec3(3,2.5,6),Vec3(.3,1,0))
    var light=Mat4.orthographic(8,.1,50)*Mat4.look_at(Vec3(5,15,5),Vec3(0,1,0))
    while device.running:
        device.poll()
        if not device.running:break
        seconds+=1.0/60 if smoke else device.input.dt
        var pose=blend_pose(rest.sample(skeleton,seconds),wave.sample(skeleton,seconds),.5+.5*sin(seconds*.5))
        var palette=skin.gpu_data(skeleton,pose)
        device.shadow_begin(light)
        device.draw_skin(handle,palette,Mat4(),shadow=True)
        device.begin(camera)
        device.draw_skin(handle,palette,Mat4(),Material(Vec3(.2,.7,.8),.5))
        device.text("ATLAS SKELETAL ANIMATION",20,20,scale=2)
        device.text("TWO JOINTS / CLIP BLEND / GPU SKINNING",20,50,scale=1)
        if smoke and frame==59:device.snapshot("build/atlas-character.bmp")
        device.present()
        frame+=1
        if smoke and frame==60:break
    device.release(handle)
    if device.validation_errors()!=0:raise Error("Character Vulkan validation failed")
    print("Atlas character passed:",frame,"frames")
