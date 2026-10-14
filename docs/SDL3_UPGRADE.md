# SDL3 3.4.18 patch upgrade

Atlas now installs and targets native SDL3 **3.4.18**, upgraded from **3.4.16**
on October 12, 2026. The project-local library and fresh Atlas backend passed
bounded C/Mojo ABI and CPU/GPU smoke verification. The complete Atlas native
build and source SDK were subsequently regenerated with the installed FFmpeg
9.0.2 CLI tooling, and the integrated checks passed.

## Upstream identity and compatibility

The [official SDL release](https://github.com/libsdl-org/SDL/releases/tag/release-3.4.18)
is marked Latest and is a stable bugfix release, published October 2, 2026.
It is not a prerelease. Its version follows the
[SDL stable version policy](https://github.com/libsdl-org/SDL/blob/main/docs/README-versions.md).
The official source archive is `SDL3-3.4.18.tar.gz`, SHA-256
`9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3`.
The downloaded bytes matched the published digest.

The installed `.deps/sdl3/lib/libSDL3.so` reports `SDL_GetVersion() == 3004018`.
Its SHA-256 is
`00372cb0b5813df5a78329687cbd03c71dedfa4807e713cd145e52abf60322c1`;
`.deps/sdl3/ATLAS-SDL3.json` records the source and library identities.

Atlas already uses native SDL3 through Mojo `std.ffi.external_call`, manual
public C layouts and `-lSDL3`. No SDL2 shim or major migration was needed.
Mojo remains **1.2.0.dev2026092905**; the root `pixi.lock` is unchanged. SDL is
built separately by CMake under `.deps`, rather than installed as a Pixi package.

Header additions cover pen device types, a Steam gamepad enum and a keyboard
code. Atlas does not bind the changed pen members or use the new enum values.
Its event storage remains 128 bytes. Fresh C/Mojo layout comparison passed;
no binding-layout or input call-site changes were required.

## Source changes

- `scripts/setup-sdl3.sh`: version, official archive digest, runtime assertion
  and a CMake cache per SDL version.
- `native/mojo/runtime.mojo`: require runtime integer `3004018` and identify
  3.4.18 in the mismatch message.
- `tests/sdl3_abi.py`: require/report 3.4.18, fail before compilation on a stale
  runtime, and honor `ATLAS_BUILD_JOBS` for Mojo compiler threads (default one).
- `tests/sdl3_window.c`: update the explicit runtime version tuple.
- `scripts/build.sh`: honor `ATLAS_BUILD_JOBS` for every Mojo build invocation
  (default one thread).
- `scripts/engine-build-state.py`: fingerprint the 3.4.18 dependency identity.
- `scripts/atlas-project.py`: exported runtime description identifies 3.4.18.
- `README.md` and `docs/SDL3_MIGRATION.md`: current patch status and a clear
  distinction from the historical 3.4.16 migration evidence.

## Verification on October 12

The build slot resumed after the parent confirmed application-settings
restoration. Stages used a **32 GiB available-memory reserve**, explicit deadlines,
one SDL build worker and one Mojo build thread. Temperatures were recorded for
observation; retired diagnostic temperature/rise guards were not restored.
No H3 workload or FFmpeg compilation ran concurrently. No shutdown or monitor
fault occurred. This does not independently establish the cause of prior shutdowns.

| Stage | Deadline | Elapsed | Result |
| --- | ---: | ---: | --- |
| Official SDL configure/build/install, `ATLAS_BUILD_JOBS=1` | 600 s | 66.10 s | Passed; runtime 3004018 |
| Fresh C/Mojo ABI oracle in activated locked environment | 120 s | 2.13 s | Passed; 36 sizes/offsets |
| Selected fresh Atlas backend and smoke-target builds | 300 s | 48.31 s | Passed; one Mojo thread |
| Dummy-driver platform/collector/keyboard/controller smoke | 30 s | 2.24 s | Passed |
| NVIDIA Vulkan window/events/editor smoke | 90 s | 4.24 s | Passed |
| Complete Atlas build and SDK regeneration | 600 s | 301.98 s | Passed |
| Combined core/platform/media/project/SDK aggregate checks | 120 s | 4.27 s | Passed |
| Rebuilt root NVIDIA window/events/editor smoke | 90 s | 4.27 s | Passed |
| Atlas image to FFmpeg H.264/decode/FFprobe pipeline | 60 s | 2.17 s | Passed |

The ABI invocation initially failed because a PATH-only launch omitted Pixi's
`MODULAR_HOME` activation and could not find `std`. It was corrected for the
verification process using the existing environment's activation setting; the
compiler/environment packages and source bindings were unchanged. The rerun
passed. This was a process-environment error, not an SDL code or thermal failure.

Runtime evidence includes SDL events, BMP/sprite/depth operations, procedural
audio, teardown and fixed-step loops; controller mapping/deadzone/reconnection;
copied UTF-8 text, key repeat/release, wheel direction, focus loss and close;
and two eight-frame real SDL/Vulkan window lifecycles with owned text input,
mouse, resize, presentation, close and reopen. The lifecycle test checks zero
Vulkan validation errors. The **60-frame Atlas editor smoke** reported
`NVIDIA GB10`, uploaded **49 chunks**, and wrote `build/atlas-world.bmp`.
The qualification process explicitly selected the NVIDIA Vulkan ICD.

Across successful stages, observed GPU maximum was **36°C**, system-sensor
maximum **48.6°C**, and minimum available memory **114.53 GiB**. Display-server
cleanup completed. Observations are sampled and do not claim an overnight soak.

Static checks also passed: archive digest, 49 recorded C header-oracle values
plus the 3.4.18 version assertion against official headers, three C harness syntax
checks, edited Bash/Python syntax, source-pin consistency and the expected
stale-runtime preflight refusal before installation.

## Artifacts, remaining work and rollback

Fresh qualification artifacts are in `build/sdl3-patch-20261012`: the native
runtime object/archive, platform/collector/editor executables and input,
controller, SDL event and window harnesses. The editor uses the separate
`build/sdl3-patch-20261012/world-project`; existing user worlds were preserved.
Linker output confirms the window harness resolves the installed project-local
SDL3 library. Root ABI evidence is refreshed in `build/sdl3-abi.json`.

The ordinary complete `scripts/build.sh` passed and refreshed the root native
archive, compiled Mojo API, examples and regression executables. Source/API/archive
fingerprints match, and `build/mojo-game-source.tar.gz` was regenerated. Its 260
manifested source files include the FFmpeg setup/wrapper/qualification scripts and
documentation. Neither the installed 493 MiB FFmpeg environment nor libav binaries
are included. An inspected player-runtime export bundles the exact SDL3 library
and the existing Mojo runtime libraries, with no FFmpeg payload or linking.

Core/world/native ABI, dummy SDL platform/audio/input/controller, asset cooker
and project/export workflow checks passed. The combined SDK check verified every
archive entry hash, optional Pixi tasks, loaded SDL identity and isolated FFmpeg/
FFprobe 9.0.2 wrappers. A first verification-harness path assertion compared an
unresolved relative RPATH as a string; it was corrected to compare resolved
library paths, and the rerun passed. This was a harness error, not an SDL regression.

FFmpeg's separately owned installation qualified FFV1 RGB/float PCM bitwise
roundtrip and H.264 encode/decode with FFprobe metadata. The final combined
pipeline also encoded the fresh 1280x800 Atlas editor image into one H.264 frame,
decoded it, and verified its dimensions/frame count through FFprobe using one CPU
thread. Output: `build/sdl3-patch-20261012/combined-editor-h264.mp4`.

The complete runtime regression suite (including broad USD/Blender qualification),
independent extracted-SDK rebuild, game-specific builds, hardware FFmpeg encoding,
stress benchmarks and overnight soak were **not run**. No unresolved code/test
failure or thermal blocker remains in the scoped checks. Pre-build root outputs
were backed up before regeneration. Optional CLI identity is tracked in its own
FFmpeg receipt and the source SDK manifest; it is not an engine libav dependency.

Detailed commands, logs, telemetry, source hashes and patch are in
`/home/user/Documents/Codex/2026-10-12/task/sdl-upgrade-20261012`.
Pre-edit sources, file modes, baseline dirty status, original SDL prefix,
overwritten ABI artifacts and prior smoke images are under its `rollback`
directory. Restore only those backed-up paths if reverting; avoid a Git reset
because the checkout contains substantial prior uncommitted work. The earlier
migration rollback under `build/sdl3-migration` is unchanged. Historical 502-check
migration evidence applies to 3.4.16 only.

No global packages, root lockfile, game sources, drivers, firmware, hardware
thermal settings or H3 launchers were modified. The separately owned FFmpeg
source additions were preserved and do not change Atlas's SDL runtime bindings.
