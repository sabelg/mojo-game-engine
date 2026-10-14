"""Independent projection checks and actual GB10 rendering of cooked USD cameras."""
from mojo_game import Graphics3D,Mesh,Mat4,Vec3,Material,Transform3D
from mojo_game.authored_lighting3d import AuthoredLighting3D
from mojo_game.authored_camera3d import AuthoredCamera3D
from std.testing import assert_true,assert_equal,assert_raises

def main() raises:
    var cameras=AuthoredCamera3D.load("build/usd-camera-fixture.atlascameras")
    assert_equal(len(cameras),2)
    var legacy=AuthoredCamera3D.load("build/usd-camera-legacy.atlascameras")
    assert_equal(legacy[0].exposure,Float64(1))
    assert_equal(cameras[0].exposure,Float64(1))
    assert_equal(cameras[0].identity,"/Perspective")
    assert_true((cameras[0].position()-Vec3(0,0,5)).length()<1e-8)
    # 36 x 24 aperture with focal length 40 => x=80/36, y=80/24.
    assert_true(abs(cameras[0].projection.data[0]-80.0/36)<1e-5)
    assert_true(abs(cameras[0].projection.data[5]-80.0/24)<1e-5)
    assert_true(abs(cameras[0].projection.data[8]-.2)<1e-5)
    assert_true(abs(cameras[1].projection.data[0]-2.0/3.6)<1e-5)
    assert_true(abs(cameras[1].projection.data[5]-2.0/2.4)<1e-5)
    with assert_raises():_=AuthoredCamera3D("bad",Mat4(),Mat4.perspective(0,1,.1,100))
    var light=AuthoredLighting3D.load("build/usd-light-fixture.atlaslights")
    assert_true((light.sun-Vec3(6,3,1.5)).length()<1e-5)
    assert_true((light.environment-Vec3(.1,.1,.1)).length()<1e-5)
    assert_true((light.direction-Vec3(0,1,0)).length()<1e-5)
    var device=Graphics3D("USD camera projection",360,240,True)
    var cube=device.upload(Mesh.cube())
    for i in range(len(cameras)):
        for shift in range(2):
            var origin=Vec3(Float64(shift)*1000000000,0,0)
            var camera=cameras[i].copy()
            camera.world.data[12]+=origin.x
            device.shadow_begin(Mat4())
            light.begin(device,camera.view_projection(origin),camera.position()-origin)
            device.draw(cube,Transform3D(origin,scale=Vec3(.8,.8,.8)).matrix(),Material(Vec3(.6,.3,.1)),origin)
            device.snapshot("build/usd-camera-"+String(i)+"-"+String(shift)+".bmp")
            assert_equal(device.validation_errors(),0)
    print("USD camera rendering passed:",device.driver(),"perspective, aperture offset, orthographic, metre conversion and billion-unit origin")
