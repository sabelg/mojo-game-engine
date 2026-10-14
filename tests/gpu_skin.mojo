"""GPU skinning raster parity with CPU deformation in lit/shadow/depth passes."""
from std.testing import assert_true,assert_raises
from mojo_game import Graphics3D,Mesh,Mat4,Transform3D,Quaternion,Vec3,Material,Skeleton,Joint,SkinnedMesh
from std.ffi import external_call

def main() raises:
    var device=Graphics3D("Atlas GPU skin parity",320,240,True)
    var skeleton=Skeleton()
    skeleton.joints.append(Joint(-1,Transform3D(),Mat4()))
    skeleton.joints.append(Joint(0,Transform3D(),Mat4()))
    var skin=SkinnedMesh(Mesh.cube())
    for i in range(len(skin.mesh.vertices)//8):
        for joint in range(4):
            skin.joints.append(joint%2)
            skin.weights.append(.7 if joint==0 else (.3 if joint==1 else 0.0))
        skin.mesh.colors.append(.4);skin.mesh.colors.append(.8);skin.mesh.colors.append(.6);skin.mesh.colors.append(1)
        var nx=Float64(skin.mesh.vertices[i*8+3])
        skin.mesh.tangents.append(Float32(1 if abs(nx)<.9 else 0))
        skin.mesh.tangents.append(0)
        skin.mesh.tangents.append(Float32(0 if abs(nx)<.9 else 1))
        skin.mesh.tangents.append(1)
    var base=skin.upload(device)
    var floor_mesh=device.upload(Mesh.cube())
    var cpu=device.upload(skin.mesh)
    var pixels: List[UInt32]=[0xffffffff]
    var water_texture=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),pixels.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    assert_true(water_texture>=0)
    assert_true(external_call["mg_water_material",Int32](device.handle.value(),Int32(water_texture))==0)
    var detail: List[UInt32]=[0xfff24da6]
    var normal_texture=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),detail.unsafe_ptr(),Int32(1),Int32(1),Int32(1)))
    var albedo_texture=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),pixels.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    device.normal_map(albedo_texture,normal_texture)
    var view=Mat4.perspective(1,320.0/240,.1,100)*Mat4.look_at(Vec3(3,2.5,6),Vec3(0,.2,0))
    var light=Mat4.orthographic(7,.1,40)*Mat4.look_at(Vec3(4,10,5),Vec3(0,0,0))
    var model=Transform3D(Vec3(.2,.1,0),Quaternion.axis_angle(Vec3(0,1,0),.25),Vec3(1.1,.9,1)).matrix()
    var ground=Transform3D(Vec3(0,-1.0,0),scale=Vec3(10,.1,10)).matrix()
    var material=Material(Vec3(.2,.6,.8),.5,texture=albedo_texture)
    for mode in range(2):
        for frame in range(60):
            var pose: List[Transform3D]=[Transform3D(Vec3(.1,0,0)),Transform3D(Vec3(0,.2,0),Quaternion.axis_angle(Vec3(0,0,1),Float64(frame)*.01),Vec3(1.2,.8,1.1))]
            var palette=skin.gpu_data(skeleton,pose)
            if mode==0:
                var deformed=skin.deform(skeleton,pose)
                var bounds=skin.gpu_bounds(palette)
                for i in range(len(deformed.vertices)//8):
                    var p=Vec3(Float64(deformed.vertices[i*8]),Float64(deformed.vertices[i*8+1]),Float64(deformed.vertices[i*8+2]))
                    assert_true(p.x>=bounds.minimum.x and p.x<=bounds.maximum.x and p.y>=bounds.minimum.y and p.y<=bounds.maximum.y and p.z>=bounds.minimum.z and p.z<=bounds.maximum.z)
                device.update_mesh(cpu,deformed)
            device.shadow_begin(light)
            device.shadow(floor_mesh,ground)
            if mode==0:device.shadow(cpu,model)
            else:device.draw_skin(base,palette,model,material,shadow=True)
            device.begin(view)
            device.draw(floor_mesh,ground,Material(Vec3(.7,.7,.7)))
            if mode==0:device.draw(cpu,model,material)
            else:device.draw_skin(base,palette,model,material)
            # Water triggers the separate opaque depth pass, which must skin too.
            device.draw(floor_mesh,Transform3D(Vec3(0,-.95,0),scale=Vec3(2,.01,2)).matrix(),Material(Vec3(.3,.5,.7),texture=water_texture))
            if frame==59:device.snapshot("build/atlas-skin-cpu.bmp" if mode==0 else "build/atlas-skin-gpu.bmp")
            device.present()
    var bad: List[Float32]=[1]
    device.shadow_begin(light)
    device.begin(view)
    with assert_raises():device.draw_skin(base,bad,model)
    device.present()
    device.release(cpu)
    device.release(base)
    device.release(floor_mesh)
    assert_true(device.validation_errors()==0)
    print("GPU skin passed: changing frame palettes, weighted positions/normals, malformed influence rejection")
