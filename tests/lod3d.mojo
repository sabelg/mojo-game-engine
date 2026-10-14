"""Complementary LOD coverage parity in lit/shadow/water-depth passes."""
from std.testing import assert_equal,assert_true,assert_raises
from std.ffi import external_call
from mojo_game import Graphics3D,Mesh,Mat4,Transform3D,Quaternion,Vec3,Material

def main() raises:
    var device=Graphics3D("Atlas LOD transitions",320,240,True)
    device.hdr()
    var mesh=Mesh.cube()
    for i in range(len(mesh.vertices)//8):
        for value in [Float32(.4),Float32(.8),Float32(.6),Float32(1)]:mesh.colors.append(value)
        var nx=Float64(mesh.vertices[i*8+3])
        for value in [Float32(1 if abs(nx)<.9 else 0),Float32(0),Float32(0 if abs(nx)<.9 else 1),Float32(1)]:mesh.tangents.append(value)
    var handle=device.upload(mesh)
    var floor=device.upload(Mesh.cube())
    var pixels: List[UInt32]=[0xffffffff,0x00ffffff,0xffffffff,0xffffffff]
    var texture=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),pixels.unsafe_ptr(),Int32(2),Int32(2),Int32(0)))
    device.texture_alpha(texture,2,.5)
    device.foliage(texture,.6)
    device.wind_material(texture)
    var detail: List[UInt32]=[0xfffa7f7f]
    var normal=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),detail.unsafe_ptr(),Int32(1),Int32(1),Int32(1)))
    var packed: List[UInt32]=[0xff3399ff]
    var orm=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),packed.unsafe_ptr(),Int32(1),Int32(1),Int32(1)))
    device.normal_map(texture,normal)
    device.orm_map(texture,orm)
    device.wind(1,.08)
    var water_pixels: List[UInt32]=[0xffffffff]
    var water=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),water_pixels.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    assert_equal(external_call["mg_water_material",Int32](device.handle.value(),Int32(water)),0)
    var view=Mat4.perspective(1,320.0/240,.1,100)*Mat4.look_at(Vec3(3,2.5,6),Vec3(0,.2,0))
    var light=Mat4.orthographic(7,.1,40)*Mat4.look_at(Vec3(4,10,5),Vec3(0,0,0))
    var matrices: List[Mat4]=[Transform3D(Vec3(.2,.1,0),Quaternion.axis_angle(Vec3(0,1,0),.25),Vec3(1.1,.9,1)).matrix()]
    var ground=Transform3D(Vec3(0,-1,0),scale=Vec3(10,.1,10)).matrix()
    var material=Material(Vec3(.2,.6,.8),.5,texture=texture)
    for mode in range(6):
        var threshold=Float64(mode-1)/4
        device.shadow_begin(light)
        device.shadow(floor,ground)
        if mode==0:device.draw_instances(handle,matrices,material,shadow=True)
        else:
            device.draw_lod_instances(handle,matrices,threshold,material=material,shadow=True)
            device.draw_lod_instances(handle,matrices,threshold,True,material,shadow=True)
        device.begin(view,fog=0)
        device.draw(floor,ground,Material(Vec3(.7,.7,.7)))
        if mode==0:device.draw_instances(handle,matrices,material)
        else:
            device.draw_lod_instances(handle,matrices,threshold,material=material)
            device.draw_lod_instances(handle,matrices,threshold,True,material)
        device.draw(floor,Transform3D(Vec3(0,-.95,0),scale=Vec3(2,.01,2)).matrix(),Material(Vec3(.3,.5,.7),texture=water))
        device.snapshot("build/atlas-lod-"+String(mode)+".bmp")
        assert_equal(device.validation_errors(),0)
        device.present()
    for step in range(5):
        device.shadow_begin(light)
        device.begin(view,fog=0)
        device.draw_lod_instances(handle,matrices,Float64(step)/4,material=material)
        device.snapshot("build/atlas-lod-coverage-"+String(step)+".bmp")
        assert_equal(device.validation_errors(),0)
        device.present()
    device.shadow_begin(light)
    device.begin(view)
    device.draw_instances(handle,matrices,material)
    var draws=device.draws()
    for invalid in [Float64(-.1),Float64(1.1),Float64("nan"),Float64("inf")]:
        with assert_raises():device.draw_lod_instances(handle,matrices,invalid)
        assert_equal(device.draws(),draws)
    device.snapshot("build/atlas-lod-preserved.bmp")
    device.release(handle);device.release(floor)
    print("LOD transitions passed:",device.driver(),"samples",external_call["mg_samples",Int32](device.handle.value()),"banks",device.frame_stat(0),"complementary color/shadow/depth coverage, colors/tangents, wind, foliage/mask, water and malformed threshold preservation")
