"""Bounded fixed-step scheduling; interpolation never extrapolates."""
struct FixedClock:
    var step: Float64
    var max_steps: Int
    var accumulator: Float64
    var elapsed: Float64
    var dropped: Float64

    def __init__(out self, hz: Float64 = 60, max_steps: Int = 8) raises:
        if hz <= 0 or max_steps < 1: raise Error("Invalid fixed clock configuration")
        self.step = 1/hz
        self.max_steps = max_steps
        self.accumulator = 0
        self.elapsed = 0
        self.dropped = 0

    def advance(mut self, dt: Float64) -> Int:
        self.accumulator += max(0.0, dt)
        var available = Int((self.accumulator+1e-12)//self.step)
        var count = min(self.max_steps, available)
        self.accumulator = max(0.0, self.accumulator-Float64(available)*self.step)
        self.elapsed += Float64(count)*self.step
        self.dropped += Float64(available-count)*self.step
        return count

    def alpha(self) -> Float64:
        return min(1.0, self.accumulator/self.step)

    def reset(mut self):
        self.accumulator = 0
        self.elapsed = 0
        self.dropped = 0
