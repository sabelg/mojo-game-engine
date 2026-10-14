> Historical planning baseline, archived October 1, 2026. Status and release numbering below are not the current plan. See [current roadmap](ROADMAP.md).

# Atlas roadmap

Updated October 1, 2026. Proposed releases below describe implementation order;
they are not calendar commitments. Atlas's current manifest version is 0.1.0.

Atlas's direction is a reusable Mojo engine for authoring and playing streamed
3D worlds on Linux ARM64 and x86-64. GB10 is the first hardware reference target.
The engine, editor and SDK must remain independent of any game project.

## Starting point

Implemented systems and their limits are documented in
[Atlas upgrades](ATLAS_UPGRADES.md), with evidence in [Validation](VALIDATION.md).

| Area | Working today | Next important gap |
| --- | --- | --- |
| Worlds | Recoverable scene/terrain saves; shared terrain/cell/collider workers | Sustained imported-world qualification |
| Rendering | Vulkan, instancing, spatial culling; cascades, FP16 HDR and SH environment | Dense-scene qualification and optional runtime temporal rendering |
| Assets | Immutable binary generations, samplers/alpha/tangents/colors, generational textures | Broader import/fuzz qualification |
| Authoring | Project import/search/properties, transforms/prefabs, terrain undo; isolated play/export smoke | Visible desktop workflow and richer docking |
| Characters | Capsule/box movement, steps, jumping and platform displacement | Imported playable-world integration and broader solver coverage |
| Animation | GPU skinning, bounds, states/events/root motion; imported reference game smoke | Sustained reference-game qualification |
| Distribution | Source SDK, independent starter, compiled API and archive checks | Automated release qualification and a supported driver matrix |

The library suite passes on lavapipe with synchronization validation and two
frames in flight. GB10 passes upload/frame resource checks and Xvfb window
resize/presentation checks. An earlier reliability build passed a 30-minute
GB10 soak (153,543 frames, zero worker errors, 1,289 commits, 208 KiB RSS change).
The scheduler/upload/frame build also passed 30 minutes: 166,390 frames, zero
worker errors and 1,397 commits. These historical builds have separate identities.
The final upgrade source passes a fresh 30-minute GB10 streaming/save run (112710
measured frames, 950 commits, zero worker errors) and a 15-minute imported-game
run (92211 frames, 428 crossings, 308 saves and clean worker shutdown).
The independent clean-SDK pipeline passes all ten phases. Frozen evidence and
remaining qualification limits are recorded in [Validation](VALIDATION.md).

Implementation is underway across this sequence. Persistent object IDs, durable
multi-cell redo transactions, repeated benchmark reports, a shared CPU scheduler,
predictive terrain priorities, reserved save capacity, terrain mesh budgets,
batched two-slot staging and two frame resource banks are implemented. Typed binary assets, immutable cooked dependency generations, safe mesh/bundle
replacement, sparse/cubic/morph imports and cooked BVH cell collision are added.
GPU skinning passes CPU raster parity in all three passes on lavapipe and GB10.
Animation states/events/root extraction, named actions, obstruction cameras and
bounded ground-navigation tiles are added. The imported independent reference
game now passes fresh GB10 route/save/reopen, NPC movement and animation-event
checks, including an independent build against the extracted SDK. Texture retirement,
sampler/alpha policies, authored tangents/colors, global terrain sculpt/paint,
project tooling and grouped prefab authoring are implemented. The editor's isolated
play passes on both drivers, and the extracted SDK passes the full suite and
Xvfb checks. Revision-driven scene caches, numeric batch identities and bounded
hierarchical culling are added, with raster and billion-unit parity checks.
Static cooked HLOD, complementary static/terrain LOD fades, cooked foliage policies
and content batching now have regression coverage. Grouped drag previews preserve
authored saves and commit/delete/duplicate selected hierarchies as one command.
Importer count/JSON/output limits and seeded mutation coverage are expanded.
An offline motion/depth temporal evaluation is reproducible; a GPU temporal mode
and high-frequency mirror maps remain future additions. Final release gates below
remain open.
Directional shadow cascades now have overlap/atlas/skin/alpha/frame-bank regression
coverage and an editor quality setting. Linear FP16 HDR, final exposure/sRGB
encoding and bounded diffuse/broad-reflection environment lighting now pass
material/water/UI/MSAA/bank/resize fixtures on both drivers. High-frequency mirror
maps and broad visual-quality qualification remain open.
Visible desktop smoke testing and other hardware/platform qualification also
remain open; passing Xvfb does not establish those gates.

## Priority and release sequence

| Order | Proposed release | Outcome | Required dependencies |
| --- | --- | --- | --- |
| 1 | 0.2 — Reliability and measurement | Reproducible performance reports and recoverable world edits | Current systems |
| 2 | 0.3 — Streaming and GPU scheduling | Sustained travel without repeated upload waits | 0.2 diagnostics and lifetime tests |
| 3 | 0.4 — Assets and world collision | Imported scenes become persistent, collidable worlds | 0.2 save recovery; 0.3 resource lifetime |
| 4 | 0.5 — Animated playable world | A reusable character explores an imported, streamed world | 0.3 and 0.4 |
| 5 | 0.6 — Authoring workflow | Import, edit, test and package from the editor | 0.4 asset/project formats; 0.5 play mode |
| 6 | 0.7 — Visual quality and scene scale | Better lighting and bounded rendering cost in dense worlds | 0.3 scheduling; 0.4 cooked assets |
| 7 | 1.0 candidate — Release qualification | Documented, repeatable support for a defined feature set | All selected feature gates and platform qualification |

Small editor improvements can proceed alongside streaming work. Asset identity
and project formats must settle before hot reload and terrain authoring. Overlapping
GPU frames must follow resource-lifetime work. Advanced visual work follows a
playable reference world so it can be measured against representative content.

## 0.2 — Reliability and measurement

**Deliverables**

- Record CPU frame stages, GPU pass timings, upload waits, queue depth, cancelled
  jobs, actual process memory, GPU allocations and pool occupancy. Distinguish
  estimated worker reservations from measured memory use.
- Add repeated benchmark runs with warmup, workload configuration, hardware/driver
  identity, source hashes, p50/p95/p99 frame times and failure summaries.
- Exercise sustained travel, repeated teleports, LOD changes, save/load errors,
  allocation failures and repeated device/worker shutdown.
- Give objects persistent identities and introduce versioned, recoverable
  multi-cell save transactions. A cross-cell move must survive interruption
  without duplicating or losing its hierarchy.
- Separate resource allocation, uploads and frame submission behind narrow
  internal interfaces in the native runtime, preserving public APIs and ABI tests.

**Completion gate:** existing regressions remain green; a 30-minute GB10 world
run has zero validation errors, retained completed jobs or continuing memory
growth after warmup. Fault-injected saves recover a consistent previous or new
world revision. Run and record swapchain/resize tests with Xvfb and a visible
desktop smoke test. Establish baselines before setting regression thresholds.

Primary code: `streaming.mojo`, `partition.mojo`, `worldeditor.mojo`,
`native/mojo/runtime.mojo`, and benchmark/test tooling.

## 0.3 — Streaming and GPU scheduling

**Deliverables**

- Replace independent single-worker queues with a shared bounded scheduler.
  Prioritize visible/near cells, incorporate camera velocity, reserve capacity
  for saves and prevent low-priority job starvation.
- Keep useful prepared results across camera updates; cancel work by request
  identity and relevance rather than discarding every queued result on a move.
- Batch uploads through a staging ring. Track submission completion explicitly
  and retire staging ranges and mesh slices against completed submissions.
- Introduce two frames in flight with separate uniforms, instance streams,
  overlays and command resources. Preserve safe snapshot and resize behavior.
- Add configurable residency budgets, backpressure and quality fallback when
  preparation or GPU submission cannot keep up. Measure coherent and staged
  paths on GB10 before choosing defaults.

**Completion gate:** travel and teleport workloads respect configured queue and
residency limits, recover to the requested neighborhood, and retain valid terrain
until replacements are ready. GPU validation passes during release, upload,
snapshot, resize and shutdown. Uploads no longer wait for each individual copy;
repeated benchmark runs show the effect on p95/p99 and memory.

Primary code: `streaming.mojo`, `world3d.mojo`, `partition.mojo`, `graphics3d.mojo`
and native allocation/submission interfaces.

## 0.4 — Assets and world collision

**Deliverables**

- Define versioned binary mesh, scene, material, skeleton and clip formats with
  size limits, checksums, dependency metadata and explicit migration rules.
  Continue loading existing scene versions.
- Preserve object, mesh and material identities through source reordering,
  recooking and reload. Diagnose missing references before publishing a project.
- Expand glTF coverage through fixture-driven additions: tangents, sampler and
  alpha settings, sparse accessors, morph data and cubic animation tracks.
  Document the supported subset and reject unsupported inputs clearly.
- Add safe asset replacement: prepare and validate new dependencies, publish the
  replacement, then retire old resources when consumers and the GPU release them.
- Cook triangle collision with a BVH and stream colliders with world cells.
  Extend capsule sweeps to imported static geometry, seams, slopes and moving
  supports. Keep render geometry and collision ownership explicit.

**Completion gate:** independently authored glTF/GLB fixtures cook deterministically,
survive source reordering and load from a clean SDK project. Asset replacement
preserves scene references. The character crosses imported stairs, slopes and cell
boundaries without tunnelling or falling through unloaded collision. Malformed
assets fail within documented allocation limits.

Primary code: cooker, `meshio.mojo`, `assets3d.mojo`, `scene3d.mojo`,
`character3d.mojo` and new collision modules.

## 0.5 — Animated playable world

**Deliverables**

- Implement GPU skinning with CPU deformation retained as a test reference;
  cover lit, shadow and depth passes and use conservative animated bounds.
- Add idle/walk/run/jump/fall states, transitions, animation events and optional
  root motion connected to the fixed-step character controller.
- Add a third-person camera with obstruction handling and input/action mapping.
- Introduce navigation tiles, basic path following and a small animated NPC test.
- Create an independent reference game with an imported character, authored
  collision, several streamed cells and a simple exploration objective. Share
  reusable services through Atlas; keep game logic and content in the game.

**Completion gate:** imported rigs match CPU reference deformation within a
specified tolerance in every relevant pass. Multiple characters exercise
transitions, culling and reload. The reference game starts from a clean project,
can traverse and save/reopen its world, and completes a repeatable gameplay run.

Primary code: `skeletal.mojo`, shaders, `character3d.mojo`, `engine3d.mojo`,
camera/navigation modules and the independent reference game.

## 0.6 — Authoring workflow

**Deliverables**

- Add project create/open, durable project settings, integrated import, dependency
  errors, searchable assets, hierarchy and property panels.
- Add move/rotate/scale tools with local/world modes, snapping, multi-selection,
  prefabs and an undo model that covers all authoring operations.
- Implement terrain sculpt/paint data with editable persistence, seam handling,
  collision updates and bounded rebuilds.
- Add play/stop with isolated simulation state, save recovery UI and engine-only
  packaging from a project. Expose relevant resource and streaming diagnostics.
- Introduce dockable panels after the underlying project and command APIs are stable.

**Completion gate:** a user can create a project, import content, author several
cells, edit terrain, test a character and export a runnable build without editing
Mojo source. Undo/redo, reopen and interrupted-save recovery preserve the world.

## 0.7 — Visual quality and scene scale

**Deliverables**

- Add cascaded directional shadows, environment lighting and a documented
  linear/HDR color pipeline with controllable exposure.
- Add hierarchical scene culling, cooked HLOD and foliage batching before
  considering GPU-driven visibility for workloads that justify it.
- Improve LOD transitions and animated/foliage bounds. Evaluate temporal
  antialiasing with motion vectors and disocclusion tests.
- Add reference scenes for material response, shadow transitions, terrain,
  animation, transparency and billion-unit coordinate precision.

**Completion gate:** visual regressions pass at fixed exposure and deterministic
time; dense-scene cost scales within the chosen budget. Every feature has a
measured quality/cost tradeoff and a working lower-cost setting.

## Performance targets to qualify

These are proposed acceptance targets, not current capabilities. Freeze content,
resolution and settings for each workload before using the targets as gates.

| Workload | Initial target | Evidence required |
| --- | --- | --- |
| Playable reference world, GB10, 1080p | Steady-travel p99 frame time at or below 16.7 ms | Repeated windowed runs; report host/GPU times separately |
| Streaming/upload work | Main-thread p99 contribution at or below 2 ms during steady travel | Stage timings, queue depth and quality/residency settings |
| Teleport recovery | Near collision and terrain available within 1 second at the pinned radius/resolution | Repeated destinations, safe loading behavior and cold/warm results |
| Memory | No growing live allocations after residency stabilizes; respect configured budgets | 30-minute measured memory and allocation traces |
| Skinning | GPU output agrees with CPU reference; cost measured across increasing character counts | Fixed rigs/clips, deformation tolerances and CPU/GPU profiles |

Change a target only with a recorded workload or product decision. Preserve the
old measurement when adjusting settings. A benchmark failure is a reason to
investigate or reduce scope, not to silently change the scene.

## 1.0 candidate — Release qualification

- Define supported platforms, devices, drivers, importer features and resource
  limits. Qualify Linux ARM64/GB10 first; add Linux x86-64 and discrete GPUs as
  hardware runners become available.
- Automate CPU, cooker, ABI, lavapipe, hardware and window tests. Extract the SDK
  on a clean runner, build it, generate an independent game and run that game.
- Add parser fuzzing, fault injection, leak/resource audits and an overnight
  streaming/editing soak. Verify recovery from interrupted saves and bad assets.
- Publish API/format migration notes, examples, reproducible benchmark reports,
  known issues and artifact checksums. Maintain engine/game boundary checks.

**Completion gate:** all advertised capabilities have reproducible acceptance
evidence on the supported matrix. SDK and reference game releases can be built
from clean sources. Remaining gaps are explicitly outside the release contract.

## Work outside this sequence

Networking and multiplayer replication, scripting/mod support, console/mobile
ports, collaborative editing and a general rigid-body solver need separate
requirements. Keep interfaces open for them, but schedule them after the reference
world establishes what the engine actually needs. New integrations should have
an explicit dependency, maintenance and licensing decision.

## Immediate next work

1. Extend the measured 4096-node cache/linear/hierarchical comparisons to
   representative imported dense and sparse worlds; retain a lower-cost setting.
2. Extend deterministic visual fixtures for cascade transitions and high-frequency
   mirror maps; current HDR/SH/cascade SDK and combined window/game paths pass.
3. Extend the measured HLOD/foliage/LOD fixtures to representative dense worlds.
   The offline motion/disocclusion evaluation precedes any GPU temporal integration.
4. Qualify the visible editor workflow and broaden parser/resource audits; grouped
   drags, duplication/deletion and bounded seeded importer fixtures are implemented.
5. Extend the frozen engine/reference-game endurance checks to overnight and
   windowed runs, and qualify the supported platform matrix and release contract.

Advance a milestone only after its completion gate passes. Keep the current
examples and independent SDK runnable throughout the work.
