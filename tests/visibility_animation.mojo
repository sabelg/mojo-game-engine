from std.testing import assert_true,assert_equal
from mojo_game import VisibilityTrack,Graphics3D,Assets3D,Scene3D,Mat4,Vec3,SceneDrawCache

def main() raises:
    var base=String("build/usd-visibility-test/cooked/visible-")
    var tracks=VisibilityTrack.load(base+"visibility.atlasvisibility")
    assert_equal(len(tracks),1)
    assert_true(not tracks[0].sample(0))
    assert_true(not tracks[0].sample(.27))
    assert_true(tracks[0].sample(6.5/24))
    assert_true(not tracks[0].sample(14.0/24))
    assert_true(tracks[0].sample(16.0/24))
    assert_true(not tracks[0].sample(100))
    var device=Graphics3D("Visibility animation",128,128,True)
    var assets=Assets3D()
    assets.load_manifest(device,base+"assets.atlasb")
    var scene=Scene3D.load(base+"scene.sceneb")
    var original=scene.encode()
    var view=Mat4.perspective(1,1,.1,100)*Mat4.look_at(Vec3(0,0,5),Vec3(0,0,0))
    var cache=SceneDrawCache()
    for mode in range(4):
        var hidden=VisibilityTrack.hidden(tracks,0.0 if mode%2==0 else .4)
        for _ in range(3):
            device.shadow_begin(Mat4())
            device.begin(view,fog=0)
            if mode<2:assets.draw(device,scene,Vec3(0,0,0),view,hidden=hidden)
            else:assets.draw_cached(device,scene,cache,0,Vec3(0,0,0),view,hidden=hidden)
            device.snapshot("build/visibility-animation-"+String(mode)+".bmp")
        assert_equal(device.validation_errors(),0)
    assert_equal(original,scene.encode())
    print("Visibility runtime passed: held interpolation, cached/uncached draws and unchanged scene nodes")
