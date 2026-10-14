"""Native Mojo renderer and input. SDL3 supplies only OS/graphics primitives."""
from std.ffi import external_call
from std.collections import Array
from mojo_game import sdl
from mojo_game.font import glyph
from mojo_game.render import Raster
from mojo_game.input import Input

@fieldwise_init
struct Color(ImplicitlyCopyable, Movable):
    var r: UInt8
    var g: UInt8
    var b: UInt8

@fieldwise_init
struct Point(ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64

struct Window:
    var textures: List[sdl.NullableHandle]
    var raster: Raster
    var window: sdl.NullableHandle
    var renderer: sdl.NullableHandle
    var running: Bool
    var started: Bool
    var paused: Bool
    var input: Input
    var last_tick: UInt64
    var frames: Int
    var smoke_frames: Int
    var initialized: Bool

    def __init__(out self, smoke_frames: Int = 0, offscreen: Bool = False, var title: String = "Mojo Game", fullscreen: Bool = True) raises:
        self.textures = List[sdl.NullableHandle]()
        self.raster = Raster()
        self.window = None
        self.renderer = None
        self.running = True
        self.started = smoke_frames > 0
        self.paused = False
        self.input = Input()
        self.last_tick = 0
        self.frames = 0
        self.smoke_frames = smoke_frames
        self.initialized = False
        try:
            sdl.check(external_call["SDL_Init", Bool](UInt32(0x20)))
            self.initialized = True
            self.window = external_call["SDL_CreateWindow", sdl.NullableHandle](
                title.as_c_string_span(),
                Int32(1100), Int32(760), UInt64(8 if offscreen else (sdl.FULLSCREEN_DESKTOP if fullscreen else 0)))
            if not self.window: raise Error(sdl.error_message())
            self.renderer = external_call["SDL_CreateRenderer", sdl.NullableHandle](self.window.value(), sdl.NullableHandle(None))
            if not self.renderer: raise Error(sdl.error_message())
            sdl.check(external_call["SDL_SetRenderLogicalPresentation", Bool](self.renderer.value(), Int32(1100), Int32(760), Int32(2)))
            self.raster.attach(self.renderer.value())
            _ = external_call["SDL_HideCursor", Bool]()
            self.last_tick = sdl.ticks()
        except err:
            self.close()
            raise err

    def close(mut self):
        for texture in self.textures:
            if texture: external_call["SDL_DestroyTexture", NoneType](texture.value())
        self.textures.clear()
        self.raster.close()
        if self.renderer:
            external_call["SDL_DestroyRenderer", NoneType](self.renderer.value())
            self.renderer = None
        if self.window:
            external_call["SDL_DestroyWindow", NoneType](self.window.value())
            self.window = None
        if self.initialized:
            _ = external_call["SDL_ShowCursor", Bool]()
            external_call["SDL_QuitSubSystem", NoneType](UInt32(0x20))
            self.initialized = False

    def __deinit__(deinit self):
        self.close()

    def poll(mut self, preserve_edges: Bool = False):
        var now = sdl.ticks()
        if now-self.last_tick < 8:
            sdl.delay(8-Int(now-self.last_tick))
            now = sdl.ticks()
        self.input.begin(min(0.05, Float64(now-self.last_tick)/1000), preserve_edges)
        self.last_tick = now
        var event = sdl.Event()
        while event.poll():
            var kind = event.kind()
            if kind == sdl.QUIT: self.running = False
            elif kind == sdl.WINDOW_FOCUS_LOST:
                self.input.lose_focus()
                if self.started and self.smoke_frames == 0:self.paused=True
            elif kind == sdl.WINDOW_CLOSE_REQUESTED:self.running=False
            elif kind == sdl.KEYDOWN or kind == sdl.KEYUP:
                self.input.key(event.scancode(),kind == sdl.KEYDOWN,event.repeat())
        var mx = Float32(0)
        var my = Float32(0)
        var buttons = external_call["SDL_GetMouseState", UInt32](Pointer(to=mx), Pointer(to=my))
        var lx = Float32(0)
        var ly = Float32(0)
        _ = external_call["SDL_RenderCoordinatesFromWindow", Bool](self.renderer.value(), mx, my, Pointer(to=lx), Pointer(to=ly))
        if self.input.focus_lost: buttons = 0
        self.input.mouse_state(Int(lx),Int(ly),buttons)
        if self.input.pressed(41): self.running = False
        self.frames += 1
        if self.smoke_frames > 0 and self.frames >= self.smoke_frames: self.running = False

    def present(self):
        _ = external_call["SDL_RenderPresent", Bool](self.renderer.value())

    def present_3d(self):
        self.raster.present(self.renderer.value())

    def color(self, c: Color):
        _ = external_call["SDL_SetRenderDrawColor", Bool](self.renderer.value(), c.r, c.g, c.b, UInt8(255))

    def raw_line(self, a: Point, b: Point):
        _ = external_call["SDL_RenderLine", Bool](self.renderer.value(), Float32(a.x), Float32(a.y), Float32(b.x), Float32(b.y))

    def line(self, a: Point, b: Point, c: Color):
        self.color(Color(c.r/5, c.g/5, c.b/5))
        self.raw_line(Point(a.x+1, a.y), Point(b.x+1, b.y))
        self.raw_line(Point(a.x-1, a.y), Point(b.x-1, b.y))
        self.raw_line(Point(a.x, a.y+1), Point(b.x, b.y+1))
        self.raw_line(Point(a.x, a.y-1), Point(b.x, b.y-1))
        self.color(c)
        self.raw_line(a, b)

    def box(self, x: Int, y: Int, w: Int, h: Int, c: Color):
        self.color(c)
        var rect = sdl.FRect(Float32(x), Float32(y), Float32(w), Float32(h))
        _ = external_call["SDL_RenderFillRect", Bool](self.renderer.value(), Pointer(to=rect))

    def text(self, message: String, x: Int, y: Int, c: Color, scale: Int = 2, center: Bool = False):
        var left = x
        if center: left -= (Int(message.byte_length())*6-1)*scale//2
        for cp in message.codepoints():
            var bits = glyph(Int(cp))
            for row in range(7):
                for col in range(5):
                    if (bits >> UInt64((6-row)*5+4-col)) & 1:
                        self.box(left+col*scale, y+row*scale, scale, scale, c)
            left += 6*scale

    def begin(mut self):
        self.raster.clear()
        self.color(Color(5, 10, 20))
        _ = external_call["SDL_RenderClear", Bool](self.renderer.value())
    def snapshot(self, var path: String) raises:
        var surface=external_call["SDL_RenderReadPixels",sdl.NullableHandle](self.renderer.value(),sdl.NullableHandle(None))
        if not surface:raise Error(sdl.error_message())
        try:sdl.check(external_call["SDL_SaveBMP",Bool](surface.value(),path.as_c_string_span()))
        except err:
            external_call["SDL_DestroySurface",NoneType](surface.value())
            raise err
        external_call["SDL_DestroySurface",NoneType](surface.value())


    def load_bitmap(mut self, var path: String) raises -> Int:
        """Load BMP into a window-owned texture; returns a stable texture ID."""
        var surface=external_call["SDL_LoadBMP",sdl.NullableHandle](path.as_c_string_span())
        if not surface: raise Error(sdl.error_message())
        var texture = external_call["SDL_CreateTextureFromSurface", sdl.NullableHandle](self.renderer.value(), surface.value())
        external_call["SDL_DestroySurface", NoneType](surface.value())
        if not texture: raise Error(sdl.error_message())
        self.textures.append(texture)
        return len(self.textures)-1

    def sprite(self, texture: Int, source: sdl.Rect, destination: sdl.Rect, angle: Float64 = 0) raises:
        """Draw a sprite sheet region. Rotation is in degrees about its center."""
        if texture < 0 or texture >= len(self.textures): raise Error("Invalid texture ID")
        if source.w <= 0 or source.h <= 0 or destination.w <= 0 or destination.h <= 0:
            raise Error("Sprite dimensions must be positive")
        var src=sdl.FRect(Float32(source.x),Float32(source.y),Float32(source.w),Float32(source.h))
        var dst=sdl.FRect(Float32(destination.x),Float32(destination.y),Float32(destination.w),Float32(destination.h))
        sdl.check(external_call["SDL_RenderTextureRotated", Bool](self.renderer.value(), self.textures[texture].value(), Pointer(to=src), Pointer(to=dst), angle, sdl.NullableHandle(None), Int32(0)))
