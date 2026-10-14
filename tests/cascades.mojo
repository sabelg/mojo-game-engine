"""Cascade fit/overlap, private uniforms, frame banks and floating-origin output."""
from mojo_game import DirectionalShadows3D,Graphics3D,Mesh,Mat4,Transform3D,Quaternion,Vec3,Material,Skeleton,Joint,SkinnedMesh,Assets3D
from mojo_game.shadows3d import unproject
from std.testing import assert_true,assert_equal,assert_raises
from std.ffi import external_call
from std.sys import argv

def main() raises:
    var device=Graphics3D("Atlas directional cascades",320,240,True)
    var hdr=False
    for arg in argv():
        if arg=="--hdr":hdr=True
    if hdr:device.hdr()
    var prefix=String("-hdr") if hdr else String()
    var cube=device.upload(Mesh.cube())
    var registry=Assets3D()
    registry.load_manifest(device,"build/atlas-cook-test/policy/policy-assets.atlas")
    var mask=registry.materials["policy/material/mask"]
    var skeleton=Skeleton()
    skeleton.joints.append(Joint(-1,Transform3D(),Mat4()))
    var skin=SkinnedMesh(Mesh.cube())
    for _ in range(len(skin.mesh.vertices)//8):
        for joint in range(4):skin.joints.append(0);skin.weights.append(1.0 if joint==0 else 0.0)
    var actor=skin.upload(device)
    var reference=device.upload(skin.mesh)
    var eye=Vec3(0,6,12)
    var forward=(Vec3(0,0,-35)-eye).unit()
    var sun=Vec3(.5,.8,.3).unit()
    var view=Mat4.perspective(1,320.0/240,.1,180)*Mat4.look_at(eye,eye+forward)
    var fit=DirectionalShadows3D(distance=140)
    fit.prepare(view,.1,180,sun,forward,eye)
    assert_equal(len(fit.matrices),4)
    var inverse=view.inverse()
    for cascade in range(4):
        var first=Float64(.1) if cascade==0 else fit.splits[cascade-1]
        var previous=Float64(.1) if cascade<2 else fit.splits[cascade-2]
        if cascade>0:first-=(first-previous)*.1
        assert_true(fit.splits[cascade]>first)
        for corner in range(4):
            var x=Float64(1 if corner&1 else -1)
            var y=Float64(1 if corner&2 else -1)
            var near=unproject(inverse,x,y,-1)
            var far=unproject(inverse,x,y,1)
            for depth in [first,fit.splits[cascade]]:
                var p=near+(far-near)*((depth-.1)/(180-.1))
                var clip=fit.matrices[cascade].point(p)
                assert_true(abs(clip.x)<=1.000001 and abs(clip.y)<=1.000001 and abs(clip.z)<=1.000001)
                var whole=fit.cull_matrix.point(p)
                assert_true(abs(whole.x)<=1.000001 and abs(whole.y)<=1.000001 and abs(whole.z)<=1.000001)
    with assert_raises():_=DirectionalShadows3D(count=3)
    with assert_raises():fit.prepare(view,.1,170,sun,forward,eye)
    assert_equal(len(fit.matrices),4)
    fit.prepare(view,.1,180,Vec3(0,1,0),forward,eye)
    var water_pixel: List[UInt32]=[0xffffffff]
    var water=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),water_pixel.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    assert_true(water>=0)
    assert_equal(external_call["mg_water_material",Int32](device.handle.value(),Int32(water)),0)
    for test in range(5):
        fit=DirectionalShadows3D(count=2 if test==0 else 4,distance=140,stabilize=False)
        var origin=Vec3(1000000000,0,1000000000) if test==2 else Vec3(0,0,0)
        fit.prepare(view,.1,180,sun,forward,eye,origin)
        for frame in range(16):
            var pose: List[Transform3D]=[Transform3D(Vec3(0,.1,0),Quaternion.axis_angle(Vec3(0,1,0),Float64(frame)*.015))]
            var palette=skin.gpu_data(skeleton,pose)
            if test==4:device.update_mesh(reference,skin.deform(skeleton,pose))
            var models=List[Mat4]()
            for i in range(4):models.append(Transform3D(origin+Vec3(Float64(i%2)*3-1.5,1,-Float64(8+i*27)),scale=Vec3(2,2,2)).matrix())
            var ground=Transform3D(origin+Vec3(0,-.25,-60),scale=Vec3(100,.5,180)).matrix()
            var masked=Transform3D(origin+Vec3(3,2,-18),scale=Vec3(1.5,2,.2)).matrix()
            var animated=Transform3D(origin+Vec3(-3,1,-14)).matrix()
            device.shadow_cascades(fit.matrices,fit.splits,forward,eye)
            if test!=3:
                device.shadow(cube,ground,origin)
                device.draw_instances(cube,models,origin=origin,shadow=True)
                device.shadow_material(cube,masked,mask.texture,origin)
                if test==4:device.shadow(reference,animated,origin)
                else:device.draw_skin(actor,palette,animated,origin=origin,shadow=True)
            device.begin(view,sun)
            device.draw(cube,ground,Material(Vec3(.7,.7,.7)),origin)
            device.draw_instances(cube,models,Material(Vec3(.3,.6,.2)),origin)
            device.draw(cube,masked,mask,origin)
            if test==4:device.draw(reference,animated,Material(Vec3(.2,.5,.8)),origin)
            else:device.draw_skin(actor,palette,animated,Material(Vec3(.2,.5,.8)),origin)
            device.draw(cube,Transform3D(origin+Vec3(0,.1,-22),scale=Vec3(4,.03,5)).matrix(),Material(Vec3(.2,.4,.6),texture=water),origin)
            if frame==15:
                device.snapshot("build/atlas-cascades"+prefix+"-"+String(test)+"-"+String(device.frame_stat(0))+".bmp")
            device.present()
    # Malformed input must not reset the frame already queued by the caller.
    device.shadow_begin(fit.matrices[0])
    device.begin(view)
    device.draw(cube,Transform3D(Vec3(0,0,-6)).matrix(),Material(Vec3(.1,.75,.2)))
    var draws=device.draws()
    var invalid=fit.splits.copy()
    invalid[1]=invalid[0]
    with assert_raises():device.shadow_cascades(fit.matrices,invalid,forward,eye)
    assert_equal(device.draws(),draws)
    with assert_raises():device.shadow_cascades(fit.matrices,fit.splits,Vec3(0,0,0),eye)
    device.present()
    # Inspect actual depth occupancy in every atlas quadrant, independent of
    # where the final perspective image happens to show tiny distant shadows.
    device.shadow_cascades(fit.matrices,fit.splits,forward,eye)
    for i in range(4):device.shadow(cube,Transform3D(Vec3(0,1,-Float64(8+i*27)),scale=Vec3(3,3,3)).matrix())
    device.begin(Mat4())
    device.shadow_debug()
    device.draw(cube,Transform3D(scale=Vec3(2,2,1)).matrix())
    device.snapshot("build/atlas-cascade-atlas"+prefix+"-"+String(device.frame_stat(0))+".bmp")
    device.present()
    device.resize(503,277)
    device.shadow_begin(fit.matrices[0])
    device.begin(Mat4.perspective(1,503.0/277,.1,180)*Mat4.look_at(eye,eye+forward),sun)
    device.draw(cube,Transform3D(Vec3(0,0,-6)).matrix(),Material(Vec3(.1,.75,.2)))
    device.snapshot("build/atlas-cascade-resized"+prefix+"-"+String(device.frame_stat(0))+".bmp")
    device.present()
    device.release(actor)
    device.release(cube)
    device.release(reference)
    registry.close(device)
    assert_equal(device.validation_errors(),0)
    print("Directional cascades passed:",device.driver(),"two/four slices, overlapping fit, skinned/alpha casters, water depth, malformed configuration and preserved public Frame layout")
