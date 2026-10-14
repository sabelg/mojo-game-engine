from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import MorphTrack,load_mesh,AnimationClip

def main() raises:
    var modes: List[String]=["LINEAR","STEP","CUBICSPLINE"]
    var expected: List[Float64]=[.5,0,1]
    for i in range(3):
        var base="build/morph-test/"+modes[i]+"/face-"
        var tracks=MorphTrack.load(base+"animation-0.atlasmorphclip")
        assert_equal(len(tracks),1)
        var weights=tracks[0].sample(1)
        assert_true(abs(weights[0]-expected[i])<1e-9)
        assert_equal(tracks[0].sample(-1)[0],Float64(0))
        assert_equal(tracks[0].sample(3)[0],Float64(1))
        var mesh=load_mesh(base+"node-0-primitive-0.atlasmeshb")
        var shaped=mesh.deform_morph(weights)
        assert_true(abs(Float64(shaped.vertices[0])-2*expected[i])<1e-6)
        var pose=AnimationClip.load(base+"animation-0.atlasclipb")
        assert_equal(len(pose.tracks),1)
    for name in [String("order"),String("nan"),String("width"),String("cubic")]:
        with assert_raises():_=MorphTrack.load("build/morph-test/"+name+".atlasmorphclip")
    print("Morph playback passed: linear/step/cubic deformation, endpoint clamps, mixed TRS and malformed tracks")
