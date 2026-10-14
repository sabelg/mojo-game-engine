from mojo_game import AuthoredCameraTrack3D,Vec3
from std.testing import assert_equal,assert_true,assert_raises

def main() raises:
    var tracks=AuthoredCameraTrack3D.load("build/usd-camera-animation.atlascameratracks")
    assert_equal(len(tracks),1)
    var camera=tracks[0].sample(.5)
    assert_true((camera.position()-Vec3(2,0,5)).length()<1e-8)
    assert_true(abs(camera.projection.data[0]-120.0/36)<1e-5)
    camera=tracks[0].sample(.51)
    assert_true((camera.position()-Vec3(2.04,0,5)).length()<1e-8)
    camera=tracks[0].sample(-1)
    assert_true(abs(camera.exposure-.5)<1e-6)
    assert_true((camera.position()-Vec3(0,0,5)).length()<1e-8)
    camera=tracks[0].sample(100)
    assert_true(abs(camera.exposure-2)<1e-6)
    assert_true((camera.position()-Vec3(4,0,5)).length()<1e-8)
    var legacy=AuthoredCameraTrack3D.load("build/usd-camera-legacy.atlascameratracks")
    assert_equal(legacy[0].sample(.5).exposure,Float64(1))
    print("USD camera playback passed: interpolation, parent motion, lens animation and endpoint clamping")
