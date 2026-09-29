"""Game lifecycle and fixed-update loop. One SDL window per process."""
from .window import Window
from .input import Input
from .timing import FixedClock

trait Game:
    def update(mut self, input: Input, dt: Float64) raises: ...
    def draw(self, mut window: Window, alpha: Float64) raises: ...

struct Engine:
    var window: Window
    var clock: FixedClock

    def __init__(out self, var title: String = "Mojo Game", hz: Float64 = 60, smoke_frames: Int = 0, offscreen: Bool = False) raises:
        self.clock = FixedClock(hz)
        self.window = Window(smoke_frames=smoke_frames, offscreen=offscreen, title=title^, fullscreen=False)
        self.window.started = True

    def run[T: Game](mut self, mut game: T) raises:
        while self.window.running:
            self.window.poll(preserve_edges=True)
            if not self.window.running: break
            if self.window.input.pressed(19):
                self.window.paused = not self.window.paused
                self.window.input.presses[19] = False
            if self.window.paused:
                self.window.input.clear_edges()
            else:
                var steps = self.clock.advance(self.window.input.dt)
                for _ in range(steps):
                    game.update(self.window.input, self.clock.step)
                    self.window.input.clear_edges()
            self.window.begin()
            game.draw(self.window, self.clock.alpha())
            self.window.present()
        self.window.close()
