"""Sprite frame playback independent of rendering and wall-clock timing."""
struct Animation(ImplicitlyCopyable, Movable):
    var first: Int
    var count: Int
    var fps: Float64
    var looping: Bool
    var time: Float64
    var finished: Bool

    def __init__(out self, first: Int, count: Int, fps: Float64, looping: Bool = True) raises:
        if first < 0 or count < 1 or fps <= 0: raise Error("Invalid animation")
        self.first = first
        self.count = count
        self.fps = fps
        self.looping = looping
        self.time = 0
        self.finished = False

    def update(mut self, dt: Float64):
        if self.finished: return
        self.time += max(0.0, dt)
        var duration = Float64(self.count)/self.fps
        if self.time >= duration:
            if self.looping: self.time -= (self.time//duration)*duration
            else:
                self.time = duration
                self.finished = True

    def frame(self) -> Int:
        return self.first+min(self.count-1, Int(self.time*self.fps+1e-10))

    def restart(mut self):
        self.time = 0
        self.finished = False
