"""Procedural laser, engine and explosion audio synthesized entirely in Mojo."""
from std.ffi import external_call
from std.math import sin
from mojo_game import sdl

@fieldwise_init
struct AudioSpec(RegisterPassable):
    var frequency: Int32
    var format: UInt16
    var channels: UInt8
    var silence: UInt8
    var samples: UInt16
    var padding: UInt16
    var size: UInt32
    var callback: sdl.NullableHandle
    var userdata: sdl.NullableHandle

struct SynthAudio:
    var device: UInt32
    var initialized: Bool
    var muted: Bool
    var laser: Float64
    var explosion: Float64
    var oscillator: Float64
    var engine_phase: Float64
    var noise: UInt32

    def __init__(out self, playback: Bool = True):
        self.device = 0
        self.initialized = False
        self.muted = False
        self.laser = 0
        self.explosion = 0
        self.oscillator = 0
        self.engine_phase = 0
        self.noise = 73
        if not playback: return
        if external_call["SDL_InitSubSystem", Int32](UInt32(0x10)) < 0:
            print("Audio unavailable; continuing silently:", sdl.error_message())
            return
        self.initialized = True
        var desired = AudioSpec(22050, 0x8010, 1, 0, 512, 0, 0, None, None)
        var obtained = AudioSpec(0, 0, 0, 0, 0, 0, 0, None, None)
        self.device = external_call["SDL_OpenAudioDevice", UInt32](sdl.NullableHandle(None), Int32(0), Pointer(to=desired), Pointer(to=obtained), Int32(0))
        if self.device == 0:
            print("Audio unavailable; continuing silently:", sdl.error_message())
            return
        external_call["SDL_PauseAudioDevice", NoneType](self.device, Int32(0))

    def close(mut self):
        if self.device != 0:
            external_call["SDL_CloseAudioDevice", NoneType](self.device)
            self.device = 0
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
        if self.device == 0: return
        if self.muted or not active:
            external_call["SDL_ClearQueuedAudio", NoneType](self.device)
            self.laser = 0
            self.explosion = 0
            return
        # Bound queued latency; synthesize at most 46 ms per video frame.
        for _ in range(4):
            if external_call["SDL_GetQueuedAudioSize", UInt32](self.device) >= 1536: break
            var samples = self.synthesize(speed, thrust, 256)
            if external_call["SDL_QueueAudio", Int32](self.device, samples.unsafe_ptr(), UInt32(512)) < 0:
                self.muted = True
                return
