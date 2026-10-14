"""Cooked foliage policy, identical-geometry batching and conservative wind bounds."""
from std.testing import assert_equal,assert_true
from mojo_game import Graphics3D,Assets3D,Scene3D,SceneDrawCache,Mat4,Vec3

def main() raises:
    var device=Graphics3D("Atlas cooked foliage",320,240,True)
    device.hdr()
    device.wind(1,.25)
    var assets=Assets3D()
    var path="build/atlas-cook-test/foliage/foliage-assets.atlasb"
    assets.load_manifest(device,path)
    var scene=Scene3D.load("build/atlas-cook-test/foliage/foliage-scene.sceneb")
    var cache=SceneDrawCache()
    var view=Mat4.perspective(1,320.0/240,.1,100)
    var light=Mat4.orthographic(12,.1,100)*Mat4.look_at(Vec3(5,8,2),Vec3(0,0,-6))
    for mode in range(2):
        device.shadow_begin(light)
        if mode==0:assets.draw(device,scene,Vec3(0,0,0),light,True,False)
        else:assets.draw_cached(device,scene,cache,1,Vec3(0,0,0),light,True)
        device.begin(view,fog=0)
        if mode==0:assets.draw(device,scene,Vec3(0,0,0),view,False,False)
        else:assets.draw_cached(device,scene,cache,1,Vec3(0,0,0),view)
        device.snapshot("build/atlas-foliage-"+String(mode)+".bmp")
        assert_equal(device.draws(),3 if mode==0 else 1)
        assert_equal(device.validation_errors(),0)
        device.present()
    assert_equal(len(assets.texture_padding),1)
    for item in cache.items:
        var original=assets.bounds[item.mesh].transformed(item.matrix)
        assert_true(abs(item.bounds.minimum.x-original.minimum.x+.25)<1e-9)
        assert_true(abs(item.bounds.maximum.z-original.maximum.z-.25)<1e-9)
    scene.nodes[1].transform.scale=Vec3(2,3,4)
    assets.prepare_scene(scene,cache,2)
    for item in cache.items:
        if item.node==4:
            var original=assets.bounds[item.mesh].transformed(item.matrix)
            assert_true(abs(item.bounds.minimum.x-original.minimum.x+.5)<1e-9)
            assert_true(abs(item.bounds.maximum.y-original.maximum.y-.75)<1e-9)
            assert_true(abs(item.bounds.maximum.z-original.maximum.z-1)<1e-9)
    # Repeated policy reloads retire their texture-keyed bound metadata as well
    # as GPU consumers; it must not grow with generational texture identities.
    for _ in range(12):
        assets.reload_manifest(device,path,scene)
        device.shadow_begin(light)
        device.begin(view)
        assets.draw_cached(device,scene,cache,2,Vec3(0,0,0),view)
        device.present()
        assets.collect(device)
        assert_equal(len(assets.texture_padding),1)
        assert_equal(len(assets.retired_textures),0)
    assets.close(device)
    assert_equal(len(assets.texture_padding),0)
    print("Cooked foliage passed:",device.driver(),"one content-identical batch, matching raster, maximum-wind bounds, scaled parents and bounded policy reload metadata")
