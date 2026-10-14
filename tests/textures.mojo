"""Reusable texture handles, pinned maps, queued consumers and import policies."""
from std.testing import assert_true,assert_equal,assert_raises
from std.ffi import external_call
from mojo_game import Graphics3D,Mesh,Mat4,Transform3D,Vec3,Material,Assets3D,Scene3D

def main() raises:
    var device=Graphics3D("Atlas texture lifetime",160,120,True)
    var mesh=device.upload(Mesh.cube())
    var pixel: List[UInt32]=[0x80ff0000]
    var texture=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),pixel.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
    assert_true(texture>=0)
    var normal=device.normal_texture("assets/ui/test-font.bmp")
    device.normal_map(texture,normal)
    assert_true(not device.texture_releasable(normal))
    var camera=Mat4.perspective(1,160.0/120,.1,100)
    var model=Transform3D(Vec3(0,0,-5)).matrix()
    device.shadow_begin(Mat4())
    device.begin(camera)
    device.draw(mesh,model,Material(texture=texture))
    assert_true(not device.texture_releasable(texture))
    device.snapshot("build/atlas-texture-first.bmp")
    device.present()
    device.wait_idle()
    device.release_texture(texture)
    assert_true(device.texture_releasable(normal))
    device.release_texture(normal)
    with assert_raises():device.texture_sampling(texture)
    with assert_raises():device.texture_alpha(texture)
    with assert_raises():device.release_texture(texture)
    device.shadow_begin(Mat4())
    device.begin(camera)
    with assert_raises():device.draw(mesh,model,Material(texture=texture))
    device.present()
    var baseline=device.allocated_bytes()
    for _ in range(300):
        var next=Int(external_call["mg_texture_pixels",Int32](device.handle.value(),pixel.unsafe_ptr(),Int32(1),Int32(1),Int32(0)))
        assert_true(next>=0 and next!=texture)
        device.texture_sampling(next,33071,33648,9728,9728)
        device.texture_alpha(next,2,.7)
        device.release_texture(next)
    assert_equal(device.allocated_bytes(),baseline)
    var assets=Assets3D()
    assets.load_manifest(device,"build/atlas-cook-test/policy/policy-assets.atlasb")
    var scene=Scene3D.load("build/atlas-cook-test/policy/policy-scene.sceneb")
    assets.validate(scene)
    for _ in range(100):
        device.shadow_begin(Mat4())
        device.begin(camera)
        var old=assets.materials["policy/material/mask"].texture
        var old_mesh=assets.handles[0]
        device.draw(old_mesh,model,Material(texture=old))
        assets.reload_manifest(device,"build/atlas-cook-test/policy/policy-assets.atlasb",scene)
        device.present()
        device.wait_idle()
        assets.collect(device)
        with assert_raises():device.texture_sampling(old)
        assert_equal(len(assets.retired_textures),0)
    for name in ["undeclared","row-path"]:
        with assert_raises():assets.reload_manifest(device,"build/atlas-cook-test/bad-binary/"+name+".atlasb",scene)
    assets.close(device)
    assert_equal(len(assets.retired_textures),0)
    device.release(mesh)
    assert_equal(device.validation_errors(),0)
    print("Texture ownership passed: 300 slot reuses, stale ids, pinned maps, queued draws, 100 bundle reloads and bounded allocations")
