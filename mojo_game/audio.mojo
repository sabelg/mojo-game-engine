"""Procedural laser, engine and explosion audio synthesized entirely in Mojo."""
from std.ffi import external_call
from std.math import sin
from mojo_game import sdl

@fieldwise_init
struct AudioSpec(RegisterPassable):
    var format: Int32
    var channels: Int32
    var frequency: Int32

struct SynthAudio:
    var device: sdl.NullableHandle
    var initialized: Bool
    var muted: Bool
    var laser: Float64
    var explosion: Float64
    var oscillator: Float64
    var engine_phase: Float64
    var noise: UInt32

    def __init__(out self, playback: Bool = True):
        self.device = None
        self.initialized = False
        self.muted = False
        self.laser = 0
        self.explosion = 0
        self.oscillator = 0
        self.engine_phase = 0
        self.noise = 73
        if not playback: return
        if not external_call["SDL_InitSubSystem", Bool](UInt32(0x10)):
            print("Audio unavailable; continuing silently:", sdl.error_message())
            return
        self.initialized = True
        var desired=AudioSpec(0x8010,1,22050)
        self.device=external_call["SDL_OpenAudioDeviceStream",sdl.NullableHandle](UInt32(0xFFFFFFFF),Pointer(to=desired),sdl.NullableHandle(None),sdl.NullableHandle(None))
        if not self.device:
            print("Audio unavailable; continuing silently:",sdl.error_message())
            return
        if not external_call["SDL_ResumeAudioStreamDevice",Bool](self.device.value()):self.muted=True

    def close(mut self):
        if self.device:
            external_call["SDL_DestroyAudioStream", NoneType](self.device.value())
            self.device = None
        if self.initialized:
            external_call["SDL_QuitSubSystem", NoneType](UInt32(0x10))
            self.initialized = False

    def __deinit__(deinit self):
        self.close()

    def trigger_laser(mut self):
        self.laser = 1

    def trigger_explosion(mut self):
        self.explosion = 1

    def synthesize(mut self, speed: Float64, thrust: Bool, count: Int, active: Bool = True) -> List[Int16]:
        var samples = List[Int16](length=count, fill=0)
        if not active or self.muted: return samples^
        for i in range(count):
            self.oscillator += (200+1500*self.laser)*6.283185307/22050
            self.engine_phase += (45+speed*0.1)*6.283185307/22050
            self.noise = self.noise*UInt32(1664525)+UInt32(1013904223)
            var noise = Float64(self.noise & 65535)/32768-1
            var value = sin(self.oscillator)*self.laser*0.18
            value += noise*self.explosion*0.27
            value += sin(self.engine_phase)*(0.045 if thrust else 0.012)
            self.laser = max(0.0, self.laser-1.0/2205)
            self.explosion = max(0.0, self.explosion-1.0/8820)
            samples[i] = Int16(max(-1.0, min(1.0, value))*24000)
        return samples^

    def update(mut self, speed: Float64, thrust: Bool, active: Bool, toggle: Bool):
        if toggle: self.muted = not self.muted
        if not self.device: return
        if self.muted or not active:
            _ = external_call["SDL_ClearAudioStream", Bool](self.device.value())
            self.laser = 0
            self.explosion = 0
            return
        # Bound queued latency; synthesize at most 46 ms per video frame.
        for _ in range(4):
            if external_call["SDL_GetAudioStreamQueued", Int32](self.device.value()) >= 1536: break
            var samples = self.synthesize(speed, thrust, 256)
            if not external_call["SDL_PutAudioStreamData", Bool](self.device.value(), samples.unsafe_ptr(), Int32(512)):
                self.muted = True
                return
