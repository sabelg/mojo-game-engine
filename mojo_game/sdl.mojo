"""Minimal SDL2 C bindings for the project's linux-64 target.

Opaque SDL allocations stay C-owned. Event storage is 56 bytes, aligned to
8 bytes, matching SDL2's public SDL_Event union on 64-bit Linux.
"""
from std.ffi import external_call
from std.collections import Array
from std.sys import size_of

comptime Handle = Pointer[UInt8, MutUntrackedOrigin]
comptime NullableHandle = Optional[Handle]
comptime QUIT = 0x100
comptime WINDOWEVENT = 0x200
comptime KEYDOWN = 0x300
comptime KEYUP = 0x301
comptime FULLSCREEN_DESKTOP = 0x1001

@fieldwise_init
struct Rect(TrivialRegisterPassable):
    var x: Int32
    var y: Int32
    var w: Int32
    var h: Int32

struct Event(Copyable, Movable):
    var storage: Array[UInt64, 7]

    def __init__(out self):
        self.storage = Array[UInt64, 7](fill=0)

    def kind(self) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[UInt32]()[unsafe_offset=0])

    def byte(self, offset: Int) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[UInt8]()[unsafe_offset=offset])

    def scancode(self) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[Int32]()[unsafe_offset=4])

    def keycode(self) -> Int:
        return Int(self.storage.unsafe_ptr().unsafe_bitcast[Int32]()[unsafe_offset=5])

    def poll(mut self) -> Bool:
        return external_call["SDL_PollEvent", Int32](self.storage.unsafe_ptr()) != 0

    def push_key(mut self, code: Int, scan: Int, down: Bool) raises:
        self.storage = Array[UInt64, 7](fill=0)
        var words = self.storage.unsafe_ptr().unsafe_bitcast[Int32]()
        words[unsafe_offset=0] = Int32(KEYDOWN if down else KEYUP)
        words[unsafe_offset=4] = Int32(scan)
        words[unsafe_offset=5] = Int32(code)
        if external_call["SDL_PushEvent", Int32](self.storage.unsafe_ptr()) != 1:
            raise Error(error_message())

def error_message() -> String:
    var p = external_call["SDL_GetError", Handle]()
    return String(unsafe_from_utf8_ptr=p)

def ticks() -> UInt64:
    return external_call["SDL_GetTicks64", UInt64]()

def delay(ms: Int):
    external_call["SDL_Delay", NoneType](UInt32(ms))

def check(result: Int32) raises:
    if result < 0: raise Error(error_message())

def verify_layout() raises:
    from std.testing import assert_equal
    assert_equal(size_of[Rect](), 16)
    assert_equal(size_of[Event](), 56)
