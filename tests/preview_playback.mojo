from std.testing import assert_true,assert_equal
from mojo_game import Graphics3D,Assets3D,Scene3D,PreviewPlayback,Vec3,Mat4

def main() raises:
    var prefix=String("build/usd-playback-cooked/preview")
    var device=Graphics3D("USD playback regression",128,128,True)
    var assets=Assets3D()
    assets.load_manifest(device,prefix+"-assets.atlasb")
    var scene=Scene3D.load(prefix+"-scene.sceneb")
    var player=PreviewPlayback.load(prefix,scene,assets)
    assert_true(len(player.skins)>0 and len(player.weights)>0)
    assert_true(abs(player.duration-4.0/24)<1e-6)
    var start=player.apply(device,assets,0)
    var first=assets.bounds[player.skin_assets[0]]
    var end=player.apply(device,assets,player.duration)
    var last=assets.bounds[player.skin_assets[0]]
    assert_true((first.minimum-last.minimum).length()>.1)
    var returned=player.apply(device,assets,0)
    assert_true((assets.bounds[player.skin_assets[0]].minimum-first.minimum).length()<1e-6)
    assert_equal(len(start),len(scene.nodes))
    assert_equal(len(end),len(start))
    assert_equal(len(returned),len(start))
    assets.close(device)
    assert_equal(device.validation_errors(),0)
    print("Preview playback passed: skin+morph deformation, dynamic bounds and reversible seeking")
