from mojo_game import Graphics3D,Mesh,Mat4,Vec3,Vec2,Material,LocalLight3D,Transform3D
from std.testing import assert_true,assert_equal,assert_raises

def main() raises:
    var device=Graphics3D("Atlas local lights",128,128,True)
    device.hdr()
    var mesh=Mesh()
    mesh.triangle(Vec3(-2,-2,0),Vec3(2,-2,0),Vec3(0,2,0))
    var handle=device.upload(mesh)
    var view=Mat4.perspective(1,1,.1,100)*Mat4.look_at(Vec3(0,0,5),Vec3(0,0,0))
    for mode in range(7):
        var lights=List[LocalLight3D]()
        var origin=Vec3(1000000000,0,0) if mode==6 else Vec3(0,0,0)
        if mode==1 or mode==6:lights.append(LocalLight3D(origin+Vec3(0,0,2),Vec3(8,4,2)))
        if mode==2:lights.append(LocalLight3D(Vec3(0,0,4),Vec3(32,16,8)))
        if mode==3:lights.append(LocalLight3D.spot(Vec3(0,0,2),Vec3(8,4,2),Vec3(0,0,-1),.2,.4))
        if mode==4:lights.append(LocalLight3D.spot(Vec3(0,0,2),Vec3(8,4,2),Vec3(0,0,1),.2,.4))
        if mode==5:
            for _ in range(32):lights.append(LocalLight3D(Vec3(0,0,2),Vec3(.25,.125,.0625)))
        device.local_lights(lights,origin)
        if mode==1:
            with assert_raises():device.local_lights(List[LocalLight3D](length=33,fill=LocalLight3D(Vec3(0,0,2),Vec3(1,1,1))))
            with assert_raises():device.local_lights([LocalLight3D(Vec3(0,0,2),Vec3(-1,0,0))])
        for _ in range(3):
            device.shadow_begin(Mat4())
            device.begin(view,fog=0)
            device.camera_origin(Vec3(0,0,5))
            device.lighting(Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0))
            device.draw(handle,Transform3D(origin).matrix(),Material(Vec3(.7,.7,.7),roughness=.8),origin)
            device.snapshot("build/local-light-"+String(mode)+".bmp")
            assert_equal(device.validation_errors(),0)
    print("Local lights passed:",device.driver(),"point, spot, 32 lights, failed-update atomicity and floating origin")
