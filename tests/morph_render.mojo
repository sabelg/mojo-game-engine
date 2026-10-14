from std.testing import assert_equal,assert_true
from mojo_game import MorphTrack,load_mesh,Graphics3D,Mat4,Vec3,Material,Transform3D

def main() raises:
    var base=String("build/morph-test/LINEAR/face-")
    var track=MorphTrack.load(base+"animation-0.atlasmorphclip")
    var mesh=load_mesh(base+"node-0-primitive-0.atlasmeshb")
    var device=Graphics3D("Morph deformation",128,128,True)
    var handle=device.upload(mesh.deform_morph([Float64(0)]))
    var reference=device.upload(mesh.deform_morph([Float64(0)]))
    var view=Mat4.perspective(1,1,.1,100)*Mat4.look_at(Vec3(1,.5,6),Vec3(1,.5,0))
    for sample in range(3):
        var weight=track[0].sample(Float64(sample))
        var deformed=mesh.deform_morph(weight)
        device.update_mesh(handle,deformed)
        for mode in range(2):
            for _ in range(3):
                device.shadow_begin(Mat4())
                device.begin(view,fog=0)
                var transform=Transform3D(Vec3(2*weight[0],0,0)) if mode==1 else Transform3D()
                device.draw(reference if mode==1 else handle,transform.matrix(),Material())
                device.snapshot("build/morph-render-"+String(sample)+"-"+String(mode)+".bmp")
                assert_equal(device.validation_errors(),0)
    print("Morph GPU publication passed: animated deformation through dynamic mesh updates")
