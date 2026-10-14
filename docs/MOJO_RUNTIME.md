# Mojo CPU runtime and project boundaries

The generic backend, compiled API and ABI tests are Atlas-owned. Yo Frankie code and assets live in `games/yo-frankie/` and consume the engine as an explicit dependency. Native APIs now use the generic `mg_*` prefix. The engine never loads game audio automatically: `mg_audio_open` opens a stereo device, and `mg_audio_load(id,path)` explicitly loads/replaces a mono-converted WAV sample. Slots are bounded to 15, voices to 12, and replacing a sample cancels its voices under the device lock. Invalid loads preserve the prior sample. Paths and playback decisions belong to the game.

See [project layout](PROJECT_LAYOUT.md). Older dated migration evidence below predates the directory split; game commands now forward to the game project.


The engine and Yo Frankie CPU runtime are written in Mojo, including Vulkan
resource allocation, render passes, pipelines, draw submission, swapchains,
profiling and snapshots; mesh/BMP decoding and the bounded SDL loader worker;
controller mapping and focus handling; WAV conversion, audio mixing and callbacks.
Gameplay, physics, animation, camera, menus and asset management were already Mojo.

SDL3, libc, the Vulkan loader and NVIDIA/Mesa drivers remain external libraries.
Shaders remain GLSL, compiled to SPIR-V and embedded in static Mojo arrays by an
offline Python build tool. Other Python/Blender asset and benchmark tools are
also offline tools. None is a Python dependency for playing the game.

## Build and boundaries

```sh
pixi run bash scripts/build.sh
pixi run bash scripts/build-frankie.sh
pixi run play-hardware
```

`native/mojo/abi.mojo` defines the 64-bit SDL3/Vulkan layouts and runtime-owned
POD records. `runtime.mojo` implements the backend and exports the existing
generic `mg_*` interfaces. `runtime_support.mojo` supplies FFI helpers and
static strings. `shaders.mojo` is generated from current shader sources; its
size functions keep shader lengths correct when a shader changes.

The historical `build/libmojo_graphics.a` filename is retained for API users;
its sole member is `mojo-runtime.o`, compiled by Mojo. There is no project C
runtime object and no fallback to the old backend. The three C regression
harnesses still test the public ABI from an independent language. They link
the Mojo compiler runtime from the active Pixi environment; they are not
linked into the game. A C compiler is required only to build those harnesses.

The Pixi lockfile pins the compiler used by this migration. Process state uses
`KGEN_CompilerRT_GetOrCreateGlobal` from that compiler runtime so the main thread,
asset reader and audio callback share the same state. That API is internal:
a compiler upgrade must rerun the ABI and threaded callback regressions.

Foreign descriptors retain integer addresses. Their stack owners are explicitly
kept alive through the final foreign call, including error paths. Do not remove
the `_ = owner^` lifetime anchors. Strings and embedded SPIR-V use
`global_constant` storage with static lifetime. SDL_AudioCVT has a packed 128-byte
layout; SDL conversion and field access use its documented byte offsets.

## Verification

```sh
build/native-abi-test
SDL_AUDIODRIVER=dummy build/frankie-native-test
build/frankie-input-test
build/frankie-controller-test
pixi run bash scripts/test.sh
pixi run bash scripts/test-frankie.sh
pixi run bash scripts/test-frankie-release.sh
pixi run bash scripts/test-vulkan-window.sh
pixi run bash scripts/test-vulkan-window.sh --frankie
```

The migration was developed on native Linux aarch64. ABI guards were checked
against the installed SDL3/Vulkan C headers. Renderer, loader, audio and input
checks use software Vulkan and dummy audio where physical hardware is absent.
The current release and legacy art regeneration suites are checked separately.
The woodland merge now preserves owned row order and later scenery stages;
forest coverage counts only its original source meshes. These fixes regenerate
without rewriting the accepted scenery bytes.

The audio device now requests stereo F32 output. Source WAVs are converted to
mono; the callback advances each voice once per stereo frame, then applies
independent left/right gains. Music and interface events remain centered.
`mg_audio_spatial` is an additive public ABI entry point. The private `Voice`
record is 24 bytes; it is not an SDL or Vulkan descriptor. ABI tests include its
new gain offsets. The spatial layer computes distance/panning and collision
occlusion in Mojo; this is stereo positioning, not HRTF or convolution reverb.

Linux x86-64 is a supported build target in the lockfile but needs a native
validation run; the ABI definitions require 64-bit pointers.

The GB10 run `gb10-showcase-20260930T100829-618868` validates the first Mojo
backend build: all 25 reports, 162,338 windowed and 21,600 headless frames, zero
Vulkan validation errors, matching executable/asset hashes. Pooled synchronous
FIFO p95 is 17.47/17.52/17.60 ms for traversal/combat/transitions. It remains the
default; requested mailbox falls back to FIFO on that X11 surface.

That completed run predates the gameplay/stereo/arrival-camera pass. Benchmark
the new executable before assigning GB10 performance acceptance to it:

```sh
bash scripts/benchmark-frankie-showcase.sh
```

The previous runtime sources and executables are preserved locally under the
ignored `build/mojo-port-baseline/` for migration comparisons. That folder is
excluded from source releases and is not used by builds or launches.
