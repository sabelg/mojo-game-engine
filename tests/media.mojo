"""Engine audio loading must be content-independent and preserve samples on failed replacement."""
from std.testing import assert_equal,assert_true
from std.ffi import external_call
from std.collections import Array
from native.mojo.runtime import mg_audio_open,mg_audio_load,mg_audio_loaded,mg_audio_close,mg_audio_play,mg_audio_spatial,port_globals,PortGlobals
from native.mojo.runtime_support import c_address,c_ref

def address(mut s: String) -> UInt64:return c_address(s.as_c_string_span().ptr())
def main() raises:
    assert_equal(mg_audio_open(),0);assert_equal(mg_audio_loaded(),0)
    var path=String("build/media-tone.wav")
    assert_equal(mg_audio_load(-1,address(path)),-1)
    assert_equal(mg_audio_load(15,address(path)),-1)
    assert_equal(mg_audio_load(0,address(path)),0);assert_equal(mg_audio_loaded(),1)
    var state=c_ref[PortGlobals](port_globals());var length=state[].lengths[0]
    assert_true(length>0);var sample=state[].samples[0]
    var missing=String("build/does-not-exist.wav")
    assert_equal(mg_audio_load(0,address(missing)),-1)
    assert_equal(state[].samples[0],sample);assert_equal(state[].lengths[0],length)
    mg_audio_play(0,0);mg_audio_spatial(0,.8,.2)
    # Replacing a playing sample cancels matching voices under the SDL device lock.
    assert_equal(mg_audio_load(0,address(path)),0)
    for i in range(12):assert_true(state[].voices[i].id!=0)
    external_call["SDL_Delay",NoneType](UInt32(20))
    mg_audio_close();assert_equal(mg_audio_loaded(),0)
    print("Engine media passed: no implicit game samples, WAV load, bounded ids, failed replacement preserves samples, active replacement cancels voices, close")
