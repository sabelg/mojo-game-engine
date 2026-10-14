"""Fixed radiance/exposure, final display encoding, overlays and target lifetime."""
from mojo_game import Graphics3D,Mesh,Mat4,Vec3,Material,Environment3D,Transform3D
from std.testing import assert_equal,assert_true,assert_raises
from std.ffi import external_call

def main() raises:
    var constant=Environment3D.constant(Vec3(.2,.4,.8))
    var pixels=List[Vec3](length=64*32,fill=Vec3(.2,.4,.8))
    var projected=Environment3D.latlong(pixels,64,32)
    for direction in [Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,1),Vec3(0,-1,0)]:
        assert_true((projected.diffuse(direction)-constant.diffuse(direction)).length()<.0005)
    with assert_raises():_=Environment3D.latlong(pixels,2048,2048)
    with assert_raises():_=Environment3D.constant(Vec3(-1,0,0))
    var device=Graphics3D("Atlas linear HDR",320,240,True)
    var mesh=Mesh()
    mesh.triangle(Vec3(-.83,-.73,-.5),Vec3(.71,-.56,-.5),Vec3(.18,.81,-.5))
    var triangle=device.upload(mesh)
    var cube=device.upload(Mesh.cube())
    var banks=String(device.frame_stat(0))
    var samples=external_call["mg_samples",Int32](device.handle.value())
    var texture_pixel: List[UInt32]=[0xff204080]
    var texture=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),texture_pixel.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    assert_true(texture>=0)
    var water_pixel: List[UInt32]=[0xffffffff]
    var water=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),water_pixel.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    assert_equal(external_call["mg_water_material",Int32](device.handle.value(),Int32(water)),0)
    var baseline: UInt64=0
    for mode in range(9):
        device.hdr(mode!=0 and mode!=8)
        if mode==5:device.resize(333,251)
        if mode==6:device.resize(320,240)
        if mode==7:device.environment(constant)
        if mode==8:device.environment(constant,False)
        for _ in range(8):
            device.shadow_begin(Mat4())
            device.begin(Mat4(),fog=0)
            var exposure: Float64=.25 if mode==2 else 4.0 if mode==3 else 1.0
            device.lighting(Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0),Vec3(.2,.4,.6),exposure)
            device.draw(triangle,Mat4(),Material(Vec3(1,1,1),emission=8,texture=texture) if mode==4 else Material(Vec3(.5,.25,.125),emission=8))
            if mode==7:device.draw(cube,Transform3D(Vec3(.5,.4,-.5),scale=Vec3(.25,.25,.25)).matrix(),Material(Vec3(.8,.5,.2),metallic=.8))
            device.rect(12,12,38,18,Vec3(.1,.8,.2))
            device.snapshot("build/atlas-hdr-"+String(samples)+"-"+banks+"-"+String(mode)+".bmp")
            assert_equal(device.validation_errors(),0)
        var allocated=external_call["mg_allocated_bytes",UInt64](device.handle.value())
        if mode==0:baseline=allocated
        if mode==8:assert_equal(allocated,baseline)
    device.hdr()
    var eye=Vec3(0,3,6)
    var view=Mat4.perspective(1,320.0/240,.1,100)*Mat4.look_at(eye,Vec3(0,-.5,-4))
    for scale in range(2):
        var intensity: Float64=1.0 if scale==0 else .5
        for _ in range(8):
            device.shadow_begin(Mat4())
            device.begin(view,fog=0)
            device.camera_origin(eye)
            device.lighting(Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0),Vec3(.2,.4,.6)*intensity,1/intensity)
            device.draw(cube,Transform3D(Vec3(0,-2,-5),scale=Vec3(10,.3,12)).matrix(),Material(Vec3(.7,.2,.1),emission=4*intensity))
            device.draw(cube,Transform3D(Vec3(1,.8,-4),scale=Vec3(1.5,1.5,1.5)).matrix(),Material(Vec3(.2,.7,.3),emission=4*intensity))
            device.draw(cube,Transform3D(Vec3(0,-.5,-5),scale=Vec3(10,.1,12)).matrix(),Material(Vec3(.1,.3,.2),texture=water))
            device.rect(12,12,38,18,Vec3(.1,.8,.2))
            device.snapshot("build/atlas-hdr-water-"+String(samples)+"-"+banks+"-"+String(scale)+".bmp")
            assert_equal(device.validation_errors(),0)
    device.environment(Environment3D.hemisphere(Vec3(2,.8,.3),Vec3(.02,.05,.2)))
    for shift in range(2):
        var origin=Vec3(Float64(shift)*16,0,0)
        device.shadow_begin(Mat4())
        device.begin(Mat4.perspective(1,320.0/240,.1,100)*Mat4.look_at(eye-origin,Vec3(0,-.5,-4)-origin),fog=.025)
        device.camera_origin(eye-origin)
        if shift==1:
            with assert_raises():device.camera_origin(Vec3(1e308,0,0))
        device.lighting(Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0),Vec3(.2,.4,.6))
        device.draw(cube,Transform3D(Vec3(0,.3,-4),scale=Vec3(3,3,3)).matrix(),Material(Vec3(.9,.6,.3),roughness=.3,metallic=.9),origin)
        device.snapshot("build/atlas-hdr-eye-"+String(samples)+"-"+banks+"-"+String(shift)+".bmp")
        assert_equal(device.validation_errors(),0)
    print("HDR passed:",device.driver(),"samples",samples,"banks",banks,"linear radiance, final exposure, sRGB encoding, environment, overlays, resize and disabled allocation recovery")
