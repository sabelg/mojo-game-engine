# Validation

Run `pixi run library-test` to compile the package, Mojo backend, examples and
all tests, then run the full suite. Independent C ABI test harnesses build with
`-Wall -Wextra -Werror`; the game runtime is compiled entirely by Mojo. All four examples compile from a temporary directory against
the precompiled package rather than local source imports.

## Automated coverage

- Original core and platform regressions, plus mouse button edges/focus loss.
- Quaternion rotation, transform composition, projection rejection and
  camera-relative conversion at one-billion-unit coordinates.
- Frustum inclusion/exclusion, slab ray intersection and camera center rays.
- OBJ negative indices, polygon triangulation, generated normals and bad indices.
- Hierarchy composition, cycle rejection, scene round trips and undo/redo.
- Adjacent terrain seam heights and reduced triangle counts at distant LOD.
- Sphere bounce, nearest ray queries and terrain contact.
- World-cell dirty save, eviction and reload.
- Vulkan device, SPIR-V pipelines, shadow/color passes, BMP textures,
  resource retirement, stale handle rejection and repeated close.
- Asset-cache deduplication, bounds picking and the reusable 3D lifecycle.
- Chunk upload budgets, bounded residency and eviction after a billion-unit move.
- Pixel-identical snapshots before/after a billion-unit world translation,
  using an odd-sized framebuffer to exercise pixel-row alignment.
- Offscreen render-target resize and rejection of meshes retired after queueing.
- Optional virtual-display swapchain acquisition, presentation and repeated resize.
- Full 24-frame world smoke: 81 resident chunks, culled scene rendering, and
  image-content checks that reject empty output.
- Worker cancellation, restart, malformed cells and bounded reservations.
- Cross-cell hierarchy transfer, delta undo/redo and stable saved references.
- glTF/GLB cooking, dependency invalidation and corrupted-output repair.
- Thin-wall capsule sweeps, stepping, jumps and moving platforms.
- Skeletal clip sampling/blending and cooked-fixture deformation.
- Byte-identical individual/instanced renders, pool reuse and dynamic meshes.
- Partition-editor and skeletal-character headless smoke runs.
- Recoverable multi-cell redo transactions, checksum failures and writer locks.
- Shared worker parallelism, save reservations and isolated client cancellation.
- Batched staging, overlapping updates, frame-bank parity and individual buffers.
- Typed binary asset parity, bounded malformed payloads and dependency paths.
- Sparse accessors, cubic tangents, morph/tangent storage and source reordering.
- GPU/CPU skin raster parity for weighted positions/normals in lit/shadow/depth
  passes, changing frame palettes and malformed influence rejection.
- Interrupted animation fades, loop events/root extraction, named input/focus loss,
  camera sphere obstruction, navigation tile eviction and capsule path following.
- Generational texture slot reuse, stale handles, attached maps, queued consumers,
  repeated bundle reloads and bounded Vulkan allocations.
- Global terrain seam/LOD/color parity, owned snapshots, undo/redo, save/reopen and
  grouped interruption recovery; old GPU chunks and stale worker revisions.
- Durable project settings, asynchronous shell-free operations, repeat imports,
  independently copied exports, path/dependency rejection and safe play cleanup.
- Grouped cross-cell multi-selection, terrain undo order, prefab identities,
  property undo and local-space transforms.
- Controller action bindings, focus suppression, root-motion wall contact and
  exact navigation endpoints.
- Triangle capsules, ramps, moving supports, cooked BVH validation, cell replacement,
  bounded geometry residency, asynchronous revision replacement, malformed worker
  candidates retaining old geometry and stale collider handles.
- Scene-owned revision caches, 4,096-node hierarchical/linear visibility parity,
  partial frustums, deterministic submission order, byte-identical raster output,
  edit/asset reload invalidation, retained-cell cache ownership and billion-unit
  origin parity. Near-view and all-visible query costs are reported separately.
- Malformed importer shape/numeric/nesting failures, publication preservation and
  runtime export rejection when the player was built in another SDK environment.
- Directional cascade overlapping fit/vertical sun, actual depth in four atlas
  tiles, shadow effect, alpha/skinned casters, CPU/GPU skin parity, water depth,
  one/two frame-bank and billion-unit captures, malformed configuration preserving
  queued frames, legacy reset and resize. Origin parity disables grid stabilization.
- Linear FP16 HDR exposure/filmic/sRGB captures, sRGB texture decode, linear water
  rescaling, SH projection/material response, display-space UI, MSAA 1/4, frame-bank
  parity, resize and restoration of legacy allocations. Cascade/skin/depth paths
  are also exercised with HDR enabled.

- Read-only grouped preview/save independence and exact committed raster parity;
  selected ancestor filtering, world snapping, cross-cell undo/redo, stale source
  rejection, grouped delete/duplicate and scaled-parent child clones.
- JSON/count preflight, per-insertion bundle limits, OBJ lexical limits, repeated
  large mesh rejection under a 256 MiB process cap and 256 seeded import mutations.
- Complementary static LOD coverage in color/shadow/water depth, measured monotonic
  coverage, MSAA 1/4, frame banks, authored attributes and masked foliage wind.
- Cooked static HLOD aggregation/reduction, exact/billion-unit captures, changed-
  scene/asset fallback, registry generation checks and malformed metadata with
  unchanged native allocation totals.
- Cooked foliage policies, content-identical batching/raster parity, maximum-wind
  and scaled-parent bounds, and repeated bound-metadata retirement.
- Sync/async terrain LOD overlap, timestep progression, retained generation
  retirement, close/eviction and immediate fallback without budget headroom.
- Offline temporal algorithm reference with exact motion/depth, moving occluders,
  history rejection, supersample comparison and origin-relative equivalence. This
  does not test a Vulkan temporal renderer.

`build/open-world.bmp` is the captured world frame. The original BMP checker uses Python's standard library; asset/cascade/HDR image
checks use Pillow from the locked SDK environment. `build/gpu-origin.bmp` and
`build/gpu-far.bmp` must be byte-identical.

## What these tests do not establish

The full library and independently extracted SDK suites pass on Mesa lavapipe.
The new renderer tests, both examples and the rebuilt Yo Frankie device check
also pass on NVIDIA GB10. Instancing and optional staged device-local uploads
have Vulkan synchronization-validation coverage. Hardware measurements and their
limits are documented in [Atlas upgrades](ATLAS_UPGRADES.md). These checks do not
establish cross-vendor compatibility or production readiness. Xvfb window acquisition/presentation, snapshot and resize checks pass on both
lavapipe and GB10 with two frames in flight. A visible desktop smoke test remains
unqualified. Resource ownership has behavioral
tests and validation checks, not a full sanitizer/driver leak audit. Terrain and cell
loading have count/time budgets and estimated reservations; frame deadlines are
not guaranteed.

`pixi run vulkan-test` requires `VK_LAYER_KHRONOS_validation` and enables
synchronization validation. Validation errors fail frame rendering.
`pixi run vulkan-window-test` uses Xvfb to exercise actual SDL Vulkan surfaces,
swapchain acquisition/presentation and recreation without a desktop window.
The window test is separate because sandbox environments may prohibit its socket.

The CPU backend is now Mojo. `build/native-abi-test` guards 64-bit SDL2/Vulkan
layouts. `SDL_AUDIODRIVER=dummy build/frankie-native-test` tests loader ownership,
64 MiB/three-job preparation bounds, cancellation/restart, malformed images,
mixer gains, mute, WAV conversion and the SDL audio callback. The full renderer
and streamed upload paths are exercised by graphics and Frankie integration tests.

## Sustained GB10 evidence

Two separate frozen builds passed 30-minute validation soaks. The reliability build
processed 153,543 frames and 1,289 commits without worker errors. The later shared
scheduler, staged upload and two-frame build processed 166,390 frames and 1,397
commits with zero worker errors and no retained jobs after shutdown. Its RSS moved
from 265,832 to 266,500 KiB; the last-versus-first-quarter median change was 68 KiB.
The latter report is `build/atlas-qualification/20261001T080804Z/run-1.json`.
Concurrent development checks occurred during the soaks, so timing is observational.
These runs do not qualify later asset/collision changes or the final reference game.

## Project and reference-game workflow evidence

`build/atlas-qualification/m6-workflow-20261001T114009Z` retains build identities,
SDK manifest and regression logs for the workflow build before scene-culling
changes. The independently extracted SDK was built with its own locked environment
and passed the complete suite with synchronization validation. The host validation
layer was supplied separately; it is not shipped as part of the source SDK.
Its Xvfb surface, presentation, resize and snapshot checks also pass on lavapipe
and GB10. Isolated editor play passes on both drivers and preserves the authored
landmark after stopping and cleaning its owned simulation copy.

The independent `games/atlas-explorer` game uses only the compiled public API and
its own generated imported content. The fresh GB10 run completed 417 frames, two
cell crossings and three saved/reopened markers; it built one NPC route, moved
the NPC 7.65 metres and fired 13 animation events. The independently compiled
clean-SDK game passed the same assertions. These are functional headless checks,
not sustained frame-time, visible desktop or cross-platform qualification.

## Scene visibility evidence

`build/atlas-qualification/scene-visibility-20261001T114601Z` retains the frozen
scene-cache source/build identities, full lavapipe suite log, GB10 fixture log and
matching snapshots. The fixture contains 4,096 static nodes and selects 64 in the
near view. Across 256 queries, GB10 measured 7.03 ms linear versus 0.28 ms
hierarchical. An all-visible orthographic view measured 12.54 versus 0.42 ms after
adding a source-order fast path for a fully contained root. Partial-frustum and
billion-unit queries match the linear result, and the rendered shadow/color image
is byte-identical. These are single-run CPU query measurements, not frame-time
gates or a general dense-world performance claim. Cached linear culling remains
available for workload comparisons.

## HDR/environment SDK evidence

`build/atlas-qualification/hdr-environment-20261001T140803Z` freezes the final
camera-relative HDR implementation, root/independent SDK identities, manifests,
software/hardware captures, Xvfb mode-switch harness and matched benchmark runs.
Both full suites pass synchronization validation. Independent SDK GB10 captures
cover HDR/exposure/sRGB/water/camera-origin/MSAA/frame banks and cascades/skinning.
Custom HDR Xvfb resize and in-flight mode switches pass on both drivers. The
GB10 isolated-play workflow closes/reaps and removes its owned simulation copy.
The reference game built with the SDK environment and public API/archive passes
417 frames, two crossings, three saved markers, one NPC route and 13 animation
events. Capture driver attribution is retained in `CAPTURES.json`; the two
asynchronous-frame fixture captures remain software-Vulkan images. This historical
build predates the final scene-scale qualification below. Visible desktop/other
hardware gates remain open.

## Repeatable independent SDK qualification

After building the root engine, run
`pixi run --locked python3 scripts/qualify-sdk.py --window`. The command preserves a
new evidence directory, checks the engine fingerprint, packages/verifies/extracts
the source SDK, independently builds it, runs its complete synchronization suite,
checks legacy and HDR Xvfb windows, and builds/runs an independent generated starter.
Pass `--output` for a new destination and `--pixi` for an explicit executable.
Phase timeouts stop the process group and preserve failure logs. `summary.json`
records commands, build identities and status; `SHA256SUMS` covers top-level
evidence. Xvfb/validation layers remain host dependencies. This is the lavapipe
pipeline; hardware runs use `qualify-atlas.py` and separately attributed fixtures.
The existing engine CI matrix now invokes this pipeline after its root checks.
Local execution passes; remote CI/x86-64 execution is not established by that result.

## Final upgrade candidate evidence

`build/atlas-qualification/atlas-candidate-20261001T170237Z` retains source SDKs,
manifests, root/manual/automated SDK archive/API/editor identities, test executable
hashes, driver-attributed captures and complete logs. The engine source fingerprint
is `6d229d679fd8c7b57e9867d3b0c009371b1731fa941b74cd39be22ef23343cee`.
The root and independently built SDK APIs match. Full synchronization suites pass
on lavapipe and GB10; LOD fixtures include authored tangents, normal/ORM maps,
MSAA 1/4 and one/two banks. Preview/save isolation, grouped hierarchy commands,
cooked HLOD/fallback, foliage reload/bounds and terrain fade/paint-budget rollback
pass. GB10 isolated editor play/export and independent game smoke pass. The clean
automated SDK pipeline passes ten phases, including legacy/HDR Xvfb and a newly
generated independent starter. Native public ABI checks remain 1183/448 bytes.

The final frozen engine's 30-minute 1080p GB10 run is
`build/atlas-qualification/20261001T163636Z`. HDR/SH, four cascades, .2-second terrain
fades, staged uploads and two banks processed 112710 measured frames, 95495 uploads,
56192 fades and 950 save commits. All 99814 accepted worker jobs completed with
zero errors and empty stderr. Requested Vulkan allocation ended at 162641808 bytes;
sampled native allocation stayed constant. RSS first/last was 215612/216108 KiB,
with an 88 KiB first/last-quarter median change. Observed host median/p99 was
7.199/10.872 ms; GPU median/p99 .528/2.431 ms. These are concurrent headless
measurements, not the proposed windowed reference-world deadline.

The independently linked imported game's 15-minute 1080p run is
`build/atlas-qualification/explorer-endurance-20261001T165135Z`. It completed 92211
frames, 428 cell crossings and 308 periodic/final saves, then verified all three
markers after reopen, navigation/animation progress and zero queued/ready/busy
jobs or reserved bytes after shutdown. Worker errors and stderr were zero; peak
shared reservation was 50331648 bytes. After 600 warmup frames, sampled native
allocation stayed at 188245760 bytes; RSS first/last was 238168/238376 KiB and
quarter-median change 116 KiB. Timing/memory are sampled every 120 frames with
8 ms pacing and 1/60 simulation; they do not establish full-frame percentiles.

`build/atlas-qualification/dense-visibility-20261001T164412Z` retains three 1080p HDR
GB10 comparisons, 300 measured frames after 100 warmup per case. Uncached,
cached-linear and cached-hierarchical captures are byte-identical. With all 4096
nodes visible, host median ranges were 6.423–6.819, .756–.860 and .524–.755 ms;
GPU ranges .152–.154, .155–.162 and .153–.156 ms. The near view selects 64 nodes;
host ranges were 1.270–1.461, .316–.519 and .195–.372 ms. Three material batches
submit each color pass. This qualifies the fixed cube fixture and retains the
uncached/linear comparison; representative imported dense-world budgets remain open.

Evidence directories contain checksums and reproduction sources. The release
package updates documentation after the executable checks; metadata records the
qualified package hash and verifies that only documentation changed. Overnight
endurance, visible desktop usability, representative visual/performance targets,
full leak/parser audits and other platform/device runs remain open. Runtime TAA
remains an offline evaluation only. This candidate is not a qualified 1.0 release.
