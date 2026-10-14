# Atlas FFmpeg media tooling

Atlas's optional media CLI uses stable FFmpeg **9.0.2**, released September 18,
2026, verified against [the official release page](https://ffmpeg.org/download.html)
on October 12, 2026. It runs separately from the Mojo runtime, which currently
loads WAV audio through SDL3. There are no linked libav bindings to upgrade.
Adding this tool does not add runtime video playback or change WAV playback.

The ARM64 setup pins the conda-forge GPL package
`ffmpeg-9.0.2-gpl_h2f3dd36_103.conda`, SHA256
`9d0c599cc0834d04f20ffdffef3d7802cbf77c53807f4a9c1d49ff52fcc3d7f2`.
This CPU package includes x264/x265 dependencies; an LGPL build would not
preserve those encoders. No source compilation is required. The package and its
dependencies live under `.deps/ffmpeg-9.0.2/.pixi/envs/default`, managed by a
separate manifest and lock. Root `pixi.lock`, system packages, and the existing
`.deps/comic-tools` fallback remain intact. This setup currently targets Linux
ARM64; other architectures require a separately verified package pin.

Run installation only when the coordinated installation/build slot is free:

```sh
pixi run ffmpeg-setup
pixi run ffmpeg-check
pixi run ffmpeg-test
pixi run ffmpeg -version
pixi run ffprobe -version
```

Alternatively run the scripts directly with Bash/Python and an installed Pixi:

```sh
bash scripts/setup-ffmpeg.sh
python3 scripts/qualify-ffmpeg.py --inspect-only
python3 scripts/qualify-ffmpeg.py
bash scripts/ffmpeg.sh -version
bash scripts/ffprobe.sh -version
```

`ffmpeg-check` checks package origin/hash/build, both executable versions, and
FFV1, PCM float32, H.264, HEVC, VP9, AAC, and Opus encoder availability.
`ffmpeg-test` additionally encodes and decodes a locally generated 0.5-second
64x64 clip, checks FFV1 RGB and PCM audio bytes exactly, validates FFprobe stream
metadata, and tests H.264 encoding/decoding. Tests use bounded CPU threads and
temporary synthetic files. The receipt is `build/ffmpeg-qualification.json`.
Listed accelerators are recorded separately from tests; no hardware support,
NVENC, or GB10 GPU encode capability is claimed.

Direct executable paths from the project root are:

```text
.deps/ffmpeg-9.0.2/.pixi/envs/default/bin/ffmpeg
.deps/ffmpeg-9.0.2/.pixi/envs/default/bin/ffprobe
```

Prefer the Atlas wrappers if a caller supplies `LD_LIBRARY_PATH` or `LD_PRELOAD`:
they clear those variables in the tool process to avoid loading an incompatible
libav ABI. No global PATH, loader configuration, or library symlinks are changed.
FFmpeg 9 has newer libav ABI majors than FFmpeg 6/8; do not point existing
applications or Python bindings at its libraries without rebuilding and testing.

The dependency set includes GCC runtime, x264/x265, AOM/SVT-AV1/dav1d, VPX,
Opus/Vorbis/LAME, subtitle/font libraries, OpenSSL, Vulkan/libplacebo, SDL2,
PulseAudio/ALSA, and OpenVINO plugins. These remain isolated media dependencies;
SDL2 inside this CLI environment does not replace Atlas's SDL3. The solver and
download are limited to one solve and two downloads; setup checks for at least
32 GiB system reserve plus 2 GiB available working headroom before starting.
The isolated lock preserves resolved dependency versions after the first setup.

Rollback: stop using the new wrappers and use an existing executable by its
absolute path. The versioned `.deps/ffmpeg-9.0.2` directory can be archived after
media tools exit. No existing H3/Wan/Mara script paths are changed. Existing
tools remain available at:

```text
/home/user/mojo-gpu-puzzles/.pixi/envs/default/bin/ffmpeg          # 8.0
/home/user/mojo-game-engine/.deps/comic-tools/root/usr/bin/ffmpeg # 6.1.1-3ubuntu5
```

The source SDK includes the setup/wrapper/qualification scripts and this document.
It does not bundle installed FFmpeg executables or their dependency environment.
Redistributing FFmpeg's GPL package requires preserving its applicable notices
and source availability obligations; this optional CLI does not link into Atlas.

## Verified installation on the ThinkStation

On October 12, 2026, FFmpeg and FFprobe both reported 9.0.2, ARM64, built with
GCC 15.3.0. The isolated environment contains 124 conda-forge packages and uses
approximately 493 MiB. Both executables resolve their shared dependencies with
`$ORIGIN/../lib`; only the system C runtime/loader libraries come from outside
the environment. No libraries were missing. Runtime `ffmpeg -L` identifies
**GPL version 3 or later** (the registry's package license label is broader).

Both CPU synthetic tests passed: 12 RGB frames at 64x64/24fps and 24,000 stereo
float samples at 48kHz round-tripped bitwise through FFV1/PCM Matroska, and
H.264 encoded/decoded all 12 frames. FFprobe verified codec/frame/rate metadata.
Required HEVC, VP9, AAC, and Opus encoders were listed; they were not separately
encoded in this short test. AV1 encoders and dav1d decoding are enabled.
DRM and Vulkan are listed, with no hardware tests or NVENC claim.

During the bounded installation/test observations, available memory stayed above
115 GiB, GPU readings were 33 C, and thermal-zone readings peaked at 36.7 C.
Sampling does not establish continuous maxima. No shutdown or fault occurred.
Normal application settings and built-in hardware protections were preserved.

The previous FFmpeg/FFprobe 8.0 and 6.1.1 executables still run, and the root
Atlas lock hash remained unchanged. The combined Atlas native build and source SDK regeneration
subsequently passed with SDL3 3.4.18. See [combined patch evidence](SDL3_UPGRADE.md).

The regenerated source SDK contains the FFmpeg setup scripts, wrappers and
qualification/documentation files; it excludes the installed environment,
FFmpeg/FFprobe executables and libav libraries. The inspected Atlas player-runtime
export also excludes FFmpeg. A final integrated CPU test encoded the fresh Atlas
editor image into one H.264 frame, decoded it and verified its 1280x800 dimensions
and frame count with FFprobe. No runtime video-playback API was added.

The observed GPL version 3-or-later notice applies to this separately installed
FFmpeg CLI build. No top-level Atlas LICENSE/COPYING file was found during the
SDK inventory; this verification does not establish the engine's redistribution
permissions or infer an engine license from FFmpeg's notice. No publication or
redistribution was performed.
