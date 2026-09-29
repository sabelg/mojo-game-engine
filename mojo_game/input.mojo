"""Raw SDL scancodes: held state and per-frame press/release edges."""
from std.collections import Array

struct Input(Copyable, Movable):
    var held: Array[Bool,512]
    var presses: Array[Bool,512]
    var releases: Array[Bool,512]
    var mouse_x: Int
    var mouse_y: Int
    var mouse_dx: Int
    var mouse_dy: Int
    var mouse_presses: UInt32
    var mouse_releases: UInt32
    var mouse_buttons: UInt32
    var dt: Float64
    var focus_lost: Bool

    def __init__(out self):
        self.held = Array[Bool,512](fill=False)
        self.presses = Array[Bool,512](fill=False)
        self.releases = Array[Bool,512](fill=False)
        self.mouse_x = 0
        self.mouse_y = 0
        self.mouse_buttons = 0
        self.mouse_dx = 0
        self.mouse_dy = 0
        self.mouse_presses = 0
        self.mouse_releases = 0
        self.dt = 0
        self.focus_lost = False

    def clear_edges(mut self):
        self.mouse_presses = 0
        self.mouse_releases = 0
        self.mouse_dx = 0
        self.mouse_dy = 0
        self.presses = Array[Bool,512](fill=False)
        self.releases = Array[Bool,512](fill=False)
        self.focus_lost = False

    def begin(mut self, dt: Float64, preserve_edges: Bool = False):
        self.dt = dt
        if not preserve_edges: self.clear_edges()

    def mouse_down(self, button: Int) -> Bool:
        return button >= 1 and button <= 32 and (self.mouse_buttons & (UInt32(1) << UInt32(button-1))) != 0

    def mouse_state(mut self, x: Int, y: Int, buttons: UInt32):
        if self.mouse_buttons != 0:
            self.mouse_dx += x-self.mouse_x
            self.mouse_dy += y-self.mouse_y
        self.mouse_x = x
        self.mouse_y = y
        self.mouse_presses |= buttons & ~self.mouse_buttons
        self.mouse_releases |= self.mouse_buttons & ~buttons
        self.mouse_buttons = buttons

    def mouse_pressed(self, button: Int) -> Bool:
        return button >= 1 and button <= 32 and (self.mouse_presses & (UInt32(1) << UInt32(button-1))) != 0

    def mouse_released(self, button: Int) -> Bool:
        return button >= 1 and button <= 32 and (self.mouse_releases & (UInt32(1) << UInt32(button-1))) != 0

    def key(mut self, scan: Int, down: Bool, repeat: Bool = False):
        if scan < 0 or scan >= 512: return
        if down:
            if not repeat and not self.held[scan]: self.presses[scan] = True
        elif self.held[scan]: self.releases[scan] = True
        self.held[scan] = down

    def lose_focus(mut self):
        self.focus_lost = True
        self.mouse_releases |= self.mouse_buttons
        self.mouse_presses = 0
        self.mouse_buttons = 0
        for i in range(512):
            if self.held[i]: self.releases[i] = True
            self.held[i] = False
            self.presses[i] = False

    def down(self, scan: Int) -> Bool:
        return scan >= 0 and scan < 512 and self.held[scan]

    def pressed(self, scan: Int) -> Bool:
        return scan >= 0 and scan < 512 and self.presses[scan]

    def released(self, scan: Int) -> Bool:
        return scan >= 0 and scan < 512 and self.releases[scan]

    def axis(self, negative: Int, positive: Int) -> Float64:
        return Float64(Int(self.down(positive))-Int(self.down(negative)))
