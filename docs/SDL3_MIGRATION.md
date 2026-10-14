# Native SDL3 platform migration

The source pin was updated to **3.4.18** on October 12, 2026. The patch is installed and passed
bounded ABI and CPU/GPU smoke checks. See [patch upgrade status](SDL3_UPGRADE.md).
The migration evidence below is historical and applies to **3.4.16**.

SDL3 **3.4.16** became the engine default on Linux ARM64/GB10 on October 2, 2026.
Atlas calls SDL3 directly from Mojo; it does not use an SDL2 compatibility shim.
The operating-system SDL2 library and the pre-migration source/compiled rollback
remain available. Existing game files were not modified. Games may need to adapt
their direct SDL calls and input assumptions to the native SDL3 API.

## Build and dependency identity

```sh
bash scripts/setup-sdl3.sh
pixi run --locked bash scripts/build.sh
```

The setup script downloads the [official stable release](https://github.com/libsdl-org/SDL/releases/tag/release-3.4.16),
checks its archive SHA-256 before extraction, and compiles a project-local shared
library under `.deps/sdl3`. It does not replace system packages. An offline archive
can be supplied with `ATLAS_SDL_SOURCE_ARCHIVE`; it receives the same digest check.
The pinned archive SHA-256 is
`7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68`.

The tested SDL3 library SHA-256 is
`42aaf1b7f854651e28550759d4f51431f4423fdfe52e9912268a1c9710f698e4`.
The independently extracted SDK rebuilt the same library bytes from official
source. `.deps/sdl3/ATLAS-SDL3.json` records the installed identity. The engine
fingerprint includes the setup script and library bytes; native initialization
rejects a different runtime version. Engine executables resolve SDL3 through a
relative RPATH; generated projects link to their selected engine's SDL3 prefix.
Runtime exports bundle SDL3 with the Mojo runtime libraries.

The configured backends include X11, Wayland, Vulkan, ALSA/PulseAudio, Linux/HIDAPI
and virtual joysticks. Optional XTEST global input emulation is disabled because
its development headers were absent; Atlas does not use it. This is the tested
host configuration, not a cross-platform qualification.

## API changes

Bindings follow the pinned [SDL3 migration guide](https://wiki.libsdl.org/SDL3/README-migration)
and release headers: boolean result conventions, 128-byte events, nanosecond event
timestamps, float mouse coordinates, window flags of width 64 bits, pointer-owned
UTF-8 text, distinct window event types, native audio streams, gamepad instance
IDs, condition/thread APIs, public surface/display layouts and Vulkan extension
and surface creation APIs. Editor text input now belongs to the owned window.
Engine environment names use `SDL_VIDEO_DRIVER` and `SDL_AUDIO_DRIVER`; Blender's
separate vendor runtime remains untouched.

An independent C-header oracle compares 36 compiled Mojo sizes and offsets.
C-created events separately exercise UTF-8 copying, key repeat/release, wheel
direction, focus loss and close requests through the public input API.

## Acceptance and rollback

The M03-based migration candidate, independently built **253-file source SDK**, and
promoted root each passed **56 software and 56 GB10 checks**, including image/origin
comparisons. The isolated cumulative M04/M05 candidate passed another **83 software
and 83 GB10 checks** after its SDL3 migration. Total: **502 checks** across these
eight suites. Its renderer changes were not promoted by this dependency migration.

Additional checks covered actual Vulkan surface/acquire/present/resize, owned
window text input and mouse, close/reopen, HDR mode switches, audio, BMP/sprites,
virtual gamepad reconnection, parallel workers, texture reloads and terrain
publication. A generated game built against the extracted SDK and passed its
eight-frame smoke. The runtime export included the exact pinned SDL3 library.

`build/sdl3-migration/acceptance.json` records the frozen report identities.
`build/sdl3-migration/latest-root-rollback.txt` locates the pre-migration snapshot,
including 38 source paths, the original file modes and 99 compiled artifacts.
No commits, pushes, game-file changes or Mara project changes were made.

This completion note and README link were added after qualification. The source
SDK was regenerated and its manifest verified afterward; the tested implementation
and library identities remain unchanged. These results do not claim an overnight
soak, production-game performance or general SDL/USD/platform conformance.
M03 retains its declared finite-profile completion; M04–M10 retain their separate
acceptance gates in [the roadmap](ROADMAP.md).
