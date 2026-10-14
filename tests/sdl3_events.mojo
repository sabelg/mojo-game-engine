"""Independent SDL3 C events pass through the public Mojo editor input API."""
from mojo_game import Graphics3D
from std.ffi import external_call
from std.testing import assert_equal,assert_true,assert_false
def push(fixture: Int) raises:
    assert_equal(external_call["atlas_sdl3_fixture",Int32](Int32(fixture)),1)
def main() raises:
    var device=Graphics3D(width=64,height=64,hidden=True)
    device.poll()
    push(0);device.poll();assert_true(device.input.pressed(4));assert_true(device.input.down(4))
    push(1);device.poll();assert_false(device.input.pressed(4));assert_true(device.input.down(4))
    push(2);device.poll();assert_true(device.input.released(4));assert_false(device.input.down(4))
    push(3);device.poll();assert_equal(device.input.text,"Mara é 猫")
    push(4);device.poll();assert_equal(device.input.mouse_wheel,-3)
    push(0);device.poll();push(5);device.poll();assert_true(device.input.focus_lost);assert_false(device.input.down(4))
    push(6);device.poll();assert_false(device.running)
    device.close()
    print("SDL3 C-to-Mojo events passed: key/repeat/release, copied UTF-8 text, flipped wheel, focus loss and close")
