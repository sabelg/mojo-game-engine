from mojo_game import AuthoredLighting3D,AuthoredLightTrack3D,Vec3
from std.testing import assert_true,assert_equal

def main() raises:
    var base=AuthoredLighting3D.load("build/usd-light-animation.atlaslights")
    var tracks=AuthoredLightTrack3D.load("build/usd-light-animation.atlaslighttracks")
    assert_equal(len(tracks),2)
    var light=AuthoredLightTrack3D.evaluate(tracks,base,.5)
    assert_true((light.sun-Vec3(8,8,8)).length()<1e-5)
    assert_true((light.environment-Vec3(.2,.2,.2)).length()<1e-5)
    assert_true((light.direction-Vec3(.70710678,0,.70710678)).length()<1e-5)
    light=AuthoredLightTrack3D.evaluate(tracks,base,.51)
    assert_true(abs(light.sun.x-8.08)<1e-5)
    light=AuthoredLightTrack3D.evaluate(tracks,base,100)
    assert_true((light.environment-Vec3(.3,.3,.3)).length()<1e-5)
    print("USD light playback passed: rotation, color/intensity interpolation, dome deltas and endpoint clamping")
