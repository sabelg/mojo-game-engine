"""Edited terrain retains GPU chunks until matching worker replacements arrive."""
from std.testing import assert_equal,assert_true
from std.ffi import external_call
from mojo_game import Graphics3D,TerrainConfig,TerrainLayer,WorldStreamer,Vec3,Mat4,StreamScheduler

def main() raises:
    var device=Graphics3D("Terrain revisions",320,240,True)
    var scheduler=StreamScheduler(workers=2)
    var streamer=WorldStreamer(TerrainConfig(radius=1,resolution=8,chunks_per_update=9),asynchronous=True,scheduler=scheduler.copy())
    var layer=TerrainLayer()
    var camera=Vec3(32,30,32)
    for _ in range(2000):
        streamer.update(device,camera)
        if len(streamer.chunks)==9:break
        external_call["SDL_Delay",NoneType](UInt32(1))
    assert_equal(len(streamer.chunks),9)
    var old=streamer.chunks[streamer.find(0,0)].handle
    layer.apply(layer.brush(Vec3(64,0,32),8,4))
    streamer.set_layer(layer,1)
    assert_equal(streamer.chunks[streamer.find(0,0)].handle,old)
    layer.apply(layer.brush(Vec3(64,0,32),8,1,Vec3(.9,.2,.1),True))
    streamer.update(device,camera)
    streamer.set_layer(layer,2)
    var projection=Mat4.perspective(1,320.0/240,.1,500)*Mat4.look_at(Vec3(0,30,80),Vec3(0,0,0))
    for _ in range(2000):
        streamer.update(device,camera)
        device.shadow_begin(Mat4())
        device.begin(projection)
        streamer.draw(device,camera)
        device.present()
        var ready=True
        for chunk in streamer.chunks:
            if chunk.revision!=2:ready=False
        if ready:break
        external_call["SDL_Delay",NoneType](UInt32(1))
    for chunk in streamer.chunks:
        assert_equal(chunk.revision,2)
        assert_true(chunk.painted)
    assert_true(streamer.chunks[streamer.find(0,0)].handle!=old)
    assert_true(scheduler.stats().reserved_bytes<=64*1024*1024)
    streamer.clear(device)
    assert_equal(device.validation_errors(),0)
    print("Terrain stream passed: old chunk retained, stale revisions discarded, painted replacements and bounded shared reservations")
