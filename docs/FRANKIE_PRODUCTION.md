# Campaign production target

Scope: improve all 12 original scenes together, retain Mojo/Vulkan, and author
editable scenes, meshes and materials in Blender. Target device: NVIDIA DGX
Spark. Production quality is not yet achieved. The current pack remains a
remaster of the original geometry and baked animation poses.

## DGX Spark build and measurement

DGX Spark has an ARM64 CPU and a Vulkan-capable NVIDIA graphics stack
([NVIDIA system overview](https://docs.nvidia.com/dgx/dgx-spark/system-overview.html),
[software stack](https://docs.nvidia.com/dgx/dgx-spark-porting-guide/porting/software-requirements.html)).
Pixi now locks both linux-64 and linux-aarch64 dependencies. Build natively on
the Spark: do not transfer the x86-64 executables or `.pixi` environment.
The launcher bypasses the optional x86-64 SDK on ARM64.

Install native system development dependencies (C compiler, SDL2 development
headers/libraries, Vulkan development headers/loader, glslc, Python 3) and Pixi.
On Ubuntu, the development packages are `build-essential libsdl2-dev
libvulkan-dev glslc python3`; use the NVIDIA driver provided for the machine.
Then, from the repository root:

```sh
pixi install --locked
pixi run play
pixi run frankie-benchmark
# After building, compare another resolution without rebuilding:
python3 scripts/benchmark-frankie.py --resolution 1440p --output build/spark-1440p.json
```

The benchmark records actual driver name, host architecture, resolution,
per-scene load time, raw frame samples, p50/p95/p99 and frames exceeding
16.67 ms. Each scene receives 30 warmup frames and 180 measured frames with a
camera orbit around spawn. It does not write saves or screenshots. The renderer
currently waits for GPU completion, so these are synchronous host frame times,
not GPU timestamp durations. Loading is excluded from frame statistics.
The first load includes renderer initialization; later loads reuse textures.
Window presentation, traversal, sustained thermals and action-heavy encounters
still need separate measurements. `--quick` checks report plumbing only.

1080p at 60 FPS is a provisional measurement budget, not a measured promise.
ARM64 dependency resolution is verified; native ARM64 compilation and NVIDIA
execution remain unverified until run on the target. Local llvmpipe results
must never be presented as DGX Spark results.

## Completion gates for every scene

| Gate | Required result | Current gap |
| --- | --- | --- |
| Art | Reviewed silhouettes, clean topology/UVs, coherent authored materials, close-up and gameplay-distance review | Original character/environment geometry still forms the base |
| Animation | Continuous locomotion/action transitions, convincing contacts and reactions | Morph interpolation within baked clips; full rig/blend system absent |
| Scenario | Authored critical path, secrets, encounter pacing, readable landmarks and rewards | Original layouts retained; no complete campaign redesign |
| Gameplay | Traversal, combat, enemy behavior and scene mechanics pass end-to-end playthroughs | Original mechanic parity incomplete |
| Camera | No obstruction, abrupt collision transitions or unreadable action along complete routes | Follow/orbit improvements exist; route review outstanding |
| Rendering | Stable edges, shadows and material response in motion | Antialiasing, advanced lighting and shadow improvements outstanding |
| Performance | Target-hardware frame-time and memory budgets during traversal and combat | Spawn-orbit harness available; hardware measurements outstanding |
| Release | Save/reload, input/audio options, accessibility, packaging and long-session regression checks | Existing tests cover a subset; release review outstanding |

Apply each shared engine improvement across all scenes and review each scene
against these gates. A passing screenshot sweep establishes resource/rendering
coverage only; it is not a production-quality acceptance test. Destructible
terrain would be a separate substantial gameplay/physics/authoring system;
the present engine does not implement it.
