"""Native SDL3 bindings. Public layouts are checked against the pinned C headers."""
from std.ffi import external_call
from std.collections import Array
from std.sys import size_of
comptime Handle = Pointer[UInt8, MutUntrackedOrigin]
comptime NullableHandle = Optional[Handle]
comptime QUIT = 0x100
comptime WINDOW_FOCUS_LOST = 527
comptime WINDOW_CLOSE_REQUESTED = 528
comptime KEYDOWN = 0x300
comptime KEYUP = 0x301
comptime FULLSCREEN_DESKTOP = 1
@fieldwise_init
struct Rect(TrivialRegisterPassable):
    var x: Int32
    var y: Int32
    var w: Int32
    var h: Int32
@fieldwise_init
struct FRect(TrivialRegisterPassable):
    var x: Float32
    var y: Float32
    var w: Float32
    var h: Float32
struct Event(Copyable, Movable):
    var storage: Array[UInt64, 16]
    def __init__(out self):
        self.storage = Array[UInt64, 16](fill=0)
    def kind(self) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[UInt32]()[])
    def byte(self, offset: Int) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[UInt8]()[unsafe_offset=offset])
    def scancode(self) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[Int32]()[unsafe_offset=6])
    def keycode(self) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[UInt32]()[unsafe_offset=7])
    def repeat(self) -> Bool:
        return self.byte(37)!=0
    def text(self) -> String:
        var address=self.storage[3]
        if not address:return ""
        var data=Pointer[UInt8,MutUntrackedOrigin](unsafe_from_address=Int(address))
        # SDL owns the event string until the next poll; copy it immediately.
        for i in range(4097):
            if data[unsafe_offset=i]==0:return String(unsafe_from_utf8_ptr=data.unsafe_bitcast[Int8]())
        return ""
    def wheel(self) -> Int:
        var words=self.storage.unsafe_ptr().unsafe_bitcast[Int32]()
        return Int(words[unsafe_offset=12])*(-1 if words[unsafe_offset=8]==1 else 1)
    def poll(mut self) -> Bool:
        return external_call["SDL_PollEvent", Bool](self.storage.unsafe_ptr())
    def push_key(mut self, code: Int, scan: Int, down: Bool) raises:
        self.storage=Array[UInt64,16](fill=0)
        var words=self.storage.unsafe_ptr().unsafe_bitcast[Int32]()
        words[unsafe_offset=0]=Int32(KEYDOWN if down else KEYUP)
        words[unsafe_offset=6]=Int32(scan)
        words[unsafe_offset=7]=Int32(code)
        self.storage.unsafe_ptr().unsafe_bitcast[UInt8]()[unsafe_offset=36]=UInt8(down)
        check(external_call["SDL_PushEvent",Bool](self.storage.unsafe_ptr()))
def error_message() -> String:
    return String(unsafe_from_utf8_ptr=external_call["SDL_GetError",Handle]())
def ticks() -> UInt64:
    return external_call["SDL_GetTicks",UInt64]()
def delay(ms: Int):
    external_call["SDL_Delay",NoneType](UInt32(ms))
def check(result: Bool) raises:
    if not result:raise Error(error_message())
def verify_layout() raises:
    from std.testing import assert_equal
    assert_equal(size_of[Rect](),16)
    assert_equal(size_of[FRect](),16)
    assert_equal(size_of[Event](),128)
