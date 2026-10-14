"""Changing mapped frame data, resource retirement and synchronous captures."""
from std.sys import argv
from std.testing import assert_equal,assert_true
from mojo_game import Graphics3D,Mesh,Mat4,Vec3,Transform3D,Material

def main() raises:
    var device=Graphics3D("Atlas frame banks",240,160,True)
    var hdr=False
    for arg in argv():
        if arg=="--hdr":hdr=True
    if hdr:device.hdr()
    var prefix=String("-hdr") if hdr else String()
    var cube=Mesh.cube()
    var handle=device.upload(cube)
    var projection=Mat4.perspective(1.04719755,1.5,.1,100)
    var light=Mat4.orthographic(12,.1,50)*Mat4.look_at(Vec3(4,8,4),Vec3(0,0,-5))
    var previous=UInt64(0)
    for i in range(120):
        var model=Transform3D(Vec3(Float64(i%3)*.2,0,-5)).matrix()
        var matrices=List[Mat4]()
        # Grow mapped instance and overlay streams while earlier banks exist.
        var count=1200 if i==60 else 1
        for _ in range(count):matrices.append(model)
        device.shadow_begin(light)
        device.draw_instances(handle,matrices,shadow=True)
        device.begin(projection)
        device.draw_instances(handle,matrices,Material(Vec3(.2+Float64(i%3)*.2,.7,.4)))
        for j in range(200 if i==60 else 1):device.rect(Float64(j%20)*8,8,4,4,Vec3(.1,.2,.8))
        device.text(String(i),8,30)
        if i==119:device.snapshot("build/atlas-frames"+prefix+"-"+String(device.frame_stat(0))+".bmp")
        device.present()
        assert_equal(device.frame_stat(1),UInt64(i+1))
        if i>0 and device.frame_stat(0)==2:assert_true(device.frame_stat(3)!=previous)
        previous=device.frame_stat(3)
        # Release after submission, and force reuse on the next submission.
        device.release(handle)
        handle=device.upload(cube)
    device.release(handle)
    assert_equal(device.validation_errors(),0)
    print("Frame banks passed: changing uniforms/instances/overlays, growth, retirement and snapshot")
