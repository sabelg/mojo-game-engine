"""Run with SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy."""
from std.testing import assert_true, assert_false, assert_equal, assert_raises
from mojo_game import Window, Color, Rect, Vec3, Camera, SynthAudio, Engine, Game, Input
from mojo_game import sdl

struct Counter(Game):
    var updates: Int
    var draws: Int

    def __init__(out self):
        self.updates = 0
        self.draws = 0

    def update(mut self, input: Input, dt: Float64) raises:
        _ = input
        assert_true(dt > 0)
        self.updates += 1

    def draw(self, mut window: Window, alpha: Float64) raises:
        assert_true(alpha >= 0 and alpha <= 1)
        window.box(0, 0, 20, 20, Color(255, 0, 0))

def main() raises:
    var window = Window(offscreen=True, fullscreen=False)
    var event = sdl.Event()
    event.push_key(97, 4, True)
    window.poll()
    assert_true(window.input.pressed(4))
    window.poll()
    assert_false(window.input.pressed(4))
    assert_true(window.input.down(4))
    event.push_key(97, 4, False)
    window.poll()
    assert_true(window.input.released(4))
    window.begin()
    window.raster.dot(5, 5, 20, 0xFFFF0000)
    window.raster.dot(5, 5, 40, 0xFF0000FF)
    assert_equal(window.raster.pixels[5*1100+5], UInt32(0xFFFF0000))
    window.raster.dot(5, 5, 10, 0xFF00FF00)
    assert_equal(window.raster.pixels[5*1100+5], UInt32(0xFF00FF00))
    var camera = Camera(Vec3(0, 0, 0), Vec3(0, 0, 0), Vec3(0, 0, 1), Vec3(1, 0, 0), Vec3(0, 1, 0))
    window.raster.triangle(camera, Vec3(-10, -10, 30), Vec3(10, -10, 30), Vec3(0, 10, 30), Vec3(255, 100, 0))
    window.present_3d()
    window.box(10, 10, 30, 30, Color(255, 255, 0))
    window.text("RESOURCE TEST", 200, 100, Color(255, 255, 255))
    window.snapshot("build/platform.bmp")
    var texture = window.load_bitmap("build/platform.bmp")
    window.sprite(texture, Rect(10, 10, 30, 30), Rect(100, 100, 60, 60), 45)
    with assert_raises():
        _ = window.load_bitmap("build/nonexistent-asset.bmp")
    with assert_raises():
        window.sprite(-1, Rect(0, 0, 1, 1), Rect(0, 0, 1, 1))
    window.present()
    var audio = SynthAudio()
    audio.trigger_explosion()
    audio.update(0, False, True, False)
    audio.close()
    audio.close()
    window.close()
    window.close()
    assert_equal(len(window.textures), 0)
    var game = Counter()
    var engine = Engine("Loop test", smoke_frames=8, offscreen=True)
    engine.run(game)
    assert_true(game.updates > 0)
    assert_false(engine.window.running)
    print("Platform tests passed: SDL events, depth, BMP, sprites, audio, teardown, loop")
