"""Reusable fixed-step 3D lifecycle. Draw owns render-pass orchestration."""
from .graphics3d import Graphics3D
from .input import Input
from .timing import FixedClock

trait Game3D:
    def update(mut self, input: Input, dt: Float64) raises: ...
    def draw(mut self, device: Graphics3D, alpha: Float64) raises: ...

struct Engine3D:
    var device: Graphics3D
    var clock: FixedClock
    var paused: Bool

    def __init__(out self, var title: String = "Mojo 3D", width: Int = 1280, height: Int = 800, hz: Float64 = 60, hidden: Bool = False) raises:
        self.clock = FixedClock(hz)
        self.device = Graphics3D(title^,width,height,hidden)
        self.paused = False

    def run[T: Game3D](mut self, mut game: T, frame_limit: Int = 0) raises:
        var frames = 0
        while self.device.running:
            self.device.poll(preserve_edges=True)
            if not self.device.running: break
            if self.device.input.focus_lost: self.paused = True
            if self.device.input.pressed(19):
                self.paused = not self.paused
                self.device.input.presses[19] = False
            if self.paused: self.device.input.clear_edges()
            else:
                for _ in range(self.clock.advance(self.device.input.dt)):
                    game.update(self.device.input,self.clock.step)
                    self.device.input.clear_edges()
            game.draw(self.device,self.clock.alpha())
            self.device.present()
            frames += 1
            if frame_limit > 0 and frames >= frame_limit: break
