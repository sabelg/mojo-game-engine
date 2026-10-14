# Atlas roadmap — production authoring and playable worlds

Updated October 2, 2026 (UTC). This replaces the earlier proposed
0.2–1.0 sequence; those numbers were planning labels, not shipped releases.
The [previous baseline](ROADMAP_BASELINE_2026.md) remains available for context.
Milestone IDs below describe outcomes and dependencies, not release dates.

The objective is a reusable engine and editor that can reliably author, play and
deliver a visually demanding 3D world. Linux ARM64/GB10 is the first hardware
target. Game code, art and audio remain outside the engine SDK. A reference game
provides real workloads and visual requirements throughout this plan.

## Verified starting point

| Area | Implemented foundation | Remaining boundary |
| --- | --- | --- |
| World/runtime | Streamed terrain and cells, recoverable saves, bounded workers/uploads, collision, culling, static HLOD and foliage policies | Representative dense worlds, overnight runs and USD-driven residency remain unqualified |
| Rendering | Vulkan, cascaded directional shadows, HDR, SH environment lighting and bounded unshadowed local lights | HDR domes, area/shadowed local lights, full color management, DOF and motion blur remain open |
| USD authoring | Native persistent stage, variants/payload controls, IDs, undo/redo, revisioned viewport, up to eight named local override layers, versioned workspace persistence and qualified owned mapped source targets | Original files stay read-only; source editing is bounded to the declared filesystem profile |
| Animation | TRS/skin/morph/camera/light/visibility preview playback; numeric scalar key editing and graph | Vector/transform curve tools, tangents, richer deformation and production animation workflows remain open |
| Asset interchange | Bounded USD/GLTF cooking, portable USDZ, static Atlas scene/cell export; declared material/geometry subsets | General MaterialX, complete export round trips and independent multi-DCC qualification remain open |
| Editor/SDK | Project tools, transforms/prefabs, terrain authoring, isolated play, engine-only source package | Full visible desktop workflow, release automation and broader platform/driver support remain open |

Latest pre-roadmap USD evidence: **37 checks passed in software and 37 on GB10**,
including local-layer and keyframe editor workflows. The extracted 217-file source
SDK passed manifest verification and the local-layer regression. Frozen runs are
`build/usd-qualification/software-20261002T040350Z-8cec9d00` and
`build/usd-qualification/hardware-20261002T040423Z-131d2334`;
`build/usd-sdk-current.json` records the corresponding SDK identity.
These paths are local build evidence, not files distributed in the SDK.

Those results qualify the tested source/artifact identities and finite profile.
This documentation revision does not constitute a new build or qualification.
Earlier runtime and endurance evidence is recorded in [Validation](VALIDATION.md);
it must not be presented as a new soak of the latest USD/editor build.
See [implemented details](ATLAS_UPGRADES.md) and the machine-readable
[compatibility profile](../assets/usd/compatibility-profile.json).

## Execution sequence

M01–M03 are complete for their declared profiles; M04–M10 remain open. Work may overlap only when its listed dependencies
are met. Every milestone retains existing regressions and the engine/game boundary.

| ID | Outcome | Dependencies | Completion evidence |
| --- | --- | --- | --- |
| M01 | Durable layered projects — complete | Current local-layer milestone | Save, close, restart and reopen with layer names, order, target and opinions intact; interrupted-save recovery and unchanged source hashes |
| M02 | Safe existing-layer editing and identity — complete | M01 | Root/sublayer/reference fixtures edit the selected working copy; correct path/time mapping, conflict handling, undo and round trip; payload/proxy identity tests |
| M03 | Production animation authoring — declared profile complete | M01; M02 for referenced targets | Vector/TRS curves, interpolation tools and camera animation survive undo/reopen; render and numerical checks at keys and between keys |
| M04 | Reference lighting and camera pipeline | A frozen reference-shot workload | HDR environment, area/local shadows, texture/display color management, DOF and motion blur validated against versioned references with measured cost |
| M05 | Material graph interoperability | M04 color contract | Declared MaterialX node/texture/lobe subset passes conversion/render comparisons; unsupported graphs produce explicit diagnostics |
| M06 | Scalable geometry and deformation | M03 and asset identity from M02 | Retained prototypes, animated placements, broader curves, GPU morphs/in-betweens and bounded geometry caches pass pose, topology and resource tests |
| M07 | USD world residency and background publication | M02, M06 and current scheduler | Representative traversal, teleport, reload, cancellation and eviction stay within frozen CPU/GPU/queue budgets without stale or missing dependencies |
| M08 | Complete round trips for the declared content profile | M02, M03, M05, M06 | Atlas edits to supported animation, cameras, lights, rigs, morphs, terrain, foliage and vertex colors reopen correctly in independent DCC fixtures |
| M09 | End-to-end editor production workflow | M01–M03; integrate M04–M08 as available | Visible desktop user can create/import/edit/animate/play/save/package without source edits; recovery, diagnostics and keyboard workflows exercised |
| M10 | Qualified engine release | Selected M01–M09 scope and representative game | Clean SDK build, documented platform matrix, independent interoperability, sustained performance, fault tests and reproducible packaged reference game |

## M01 — completed implementation milestone

**Status: complete (October 1, 2026, America/Denver).**
Engine implementation responsibility: Codex. Native `save_workspace` and
`open_workspace` preserve separate owned layer names/order/opinions, target and
payload rules using synchronized immutable generations and atomic manifest
publication. The editor separates workspace save/reopen from USD/USDZ delivery
and indicates unsaved changes. History restarts empty. See
[format, limits and recovery policy](USD_WORKSPACES.md).

Final runs supplied by the user passed **40 checks on software Vulkan and 40 on
GB10**, including image/origin comparisons, workspace restart/fault tests,
editor IPC and the native workspace window. Frozen reports are
`build/usd-qualification/software-20261002T051225Z-2636b087/report.json` and
`build/usd-qualification/hardware-20261002T051303Z-e1a3b469/report.json`.
All 238 recorded source/tool/artifact hashes in each report matched the current
files before this documentation-only completion update. The warnings about
Pillow's deprecated `getdata` call did not fail either run.

`build/roadmap-m01/` retains the engine build, nine targeted authoring/workspace
regressions, software Vulkan editor smoke and the independently extracted SDK
checks. All 223 SDK manifest files were verified; its native authoring service was
compiled from extracted sources and its workspace/editor/layer regressions passed.
`baseline.json`, `baseline-status.z` and `baseline/` preserve the preexisting
working-tree baseline. The earlier sandbox/approval limitations were resolved for
M01 acceptance by the user's successful host evaluation runs; they are not a new
authorization for future outside-sandbox execution. No overnight endurance or
broader release/platform qualification is claimed. M02 completion is recorded below;
M04–M10 remain open.

Create a versioned workspace format that records original source identity,
owned layer files, layer order, selected target and payload load rules. Keep the
existing composed `save`/`package` delivery behavior distinct from workspace save.
Use portable relative paths for owned files and report missing external sources.

Implement in this order:

1. Define the workspace manifest, validation limits and recovery/version policy.
2. Add native save/open operations that write owned layers into a new generation
   and publish the manifest atomically after validation; never overwrite sources.
3. Wire editor save/open to durable workspace state; label workspace and delivery
   exports clearly and indicate unsaved changes.
4. Exercise process termination at each publication boundary, disk/write errors,
   moved project directories, missing dependencies and obsolete versions.
5. Extract the SDK, reopen a workspace there, compare layer contents and composed
   values, and run the software/GB10 suites for the exact final build.

**Done means:** two named layers with conflicting keys preserve both authored
values and their strength after restart. The selected target and payload rules
survive. A failed save leaves the previous complete workspace usable. Original
source files remain byte-identical. Cross-restart undo is a separate requirement;
M01 must document whether history restarts empty rather than imply it persists.

## Authoring and interchange details

**M02:** Stage source edits in owned working copies. Handle root/sublayers first,
then mapped reference/variant contexts and sublayer time offsets. Make read-only,
unsupported and stronger-layer-masked edits visible. Detect changed source
fingerprints and surface reload conflicts. Reconcile persistent identities across
payload unload/reload and repeated instances without treating proxies as directly
writable prims. Add asset-path relocation and duplicate-ID fixtures.

Owned filesystem source copies, mapped reference/variant and time-offset edits,
explicit conflicts, version 2 workspaces and payload/proxy identity reconciliation
are implemented and qualified. **M02 is complete (October 2, 2026, UTC).**
The user ran fresh software and GB10 evaluations after fixing snapshot layer-path
ordering; each passed **44 checks and image/origin comparisons**. Frozen reports:
`build/usd-qualification/software-20261002T070136Z-370ec58b/report.json` and
`build/usd-qualification/hardware-20261002T070217Z-898081fe/report.json`.
All 243 recorded source/tool/artifact hashes matched each other and the current
files before this documentation-only completion update. The earlier hardware
run stopped at a CPU history assertion because `GetUsedLayers()` enumeration
changed order after rollback; snapshots now emit sorted unique paths. Sixty
consecutive history runs and eleven targeted regressions passed. An independently
compiled extracted SDK verified all 228 manifest files and passed six checks.
`build/roadmap-m02/checkpoint.json` records the evidence. The non-failing Pillow
deprecation warning remains. These finite-profile runs do not qualify M03,
independent DCC interoperability or endurance. See
[the working-copy workflow](USD_WORKSPACES.md).

**M03: complete for the declared animation profile (October 2, 2026, UTC).**
Typed vector/quaternion/TRS channels, named skeleton/morph arrays, whole-key
copy/move/delete, held/linear/scalar Bézier tangent tools, explicit finite bake
and rejection, mapped physical retiming and fractional playback are implemented.
Numerical and rendered independent pose checks cover keys and intermediate times;
the representative workload has 10,000 vertices, 32 joints and two morphs.
See [the exact supported scope and exclusions](USD_TYPED_CURVES.md).

The frozen candidate and independently extracted 247-file source SDK each passed
56 software and 56 GB10 checks. Root promotion then rebuilt the engine and native
USD tools and passed fresh **56 software and 56 GB10 checks**, including image/origin
comparisons. The accepted root reports are
`build/usd-qualification/software-20261002T171230Z-0e8fdc24/report.json` and
`build/usd-qualification/hardware-20261002T172136Z-c3e34275/report.json`.

`build/roadmap-m03/root-promotion-acceptance.json` records report identities,
the independently qualified SDK, and the rollback checkpoint. These reports
precede this documentation-only status update; the SDK was regenerated afterward.
This completion claim covers the finite declared animation profile, not general
curves, all deformations, production-game acceptance or independent multi-DCC
round trips. M04–M10 retain their separate gates.

**M08:** Establish an explicit import/export feature matrix before claiming a
round trip. Preserve units, axes, IDs, hierarchy, shared assets and authored times.
Test geometry/material edits as well as cameras, lights and animation. Include
terrain/foliage conversion and vertex-color handling or document their exclusions.
A successful Blender import alone does not prove interchange with other DCCs.

## Visual and scale details

**M04:** Start with the reference scene's largest visible gaps: blue exterior/amber
interior lighting, wet surfaces, skin/hair response, readable faces and controlled
exposure. Fix scene-linear texture handling and display transforms before judging
material differences. Add HDR domes, area lights and shadowed local lights in
measured increments; qualify DOF and motion blur with temporal reference scenes.
Keep a lower-cost setting for each expensive feature.

**M05:** Freeze supported graph nodes and lobes, texture addressing, normal maps,
color spaces and alpha behavior. Expand beyond constant material approximations
through small independent fixtures before adopting whole production assets.
Coat, transmission and other advanced lobes require their own comparisons.

**M06–M07:** Retain prototypes rather than expanding every occurrence into unique
geometry. Include animated placements, deformation bounds and relevant curve
profiles. Define geometry-cache topology/size limits. Route USD payload demand,
LOD selection and renderer publication through bounded runtime scheduling, with
collision readiness and safe fallback during travel. Account for live resources,
retirement queues, GPU allocations and process memory separately.

Runtime temporal antialiasing, sharper reflection maps and broader culling/HLOD
work remain measured extensions from the earlier plan. Select them from observed
reference-scene defects and cost; they do not replace the residency and reliability
gates. General rigid-body physics, networking, collaborative editing, console/mobile
ports and Hydra integration need separate requirements before entering this sequence.

## Reference-game track

Engine compatibility and artistic fidelity have separate acceptance checks. Begin
reference review and asset creation now; they do not depend on finishing M10.
Game-specific production details stay in the game project's own roadmap.

| Stage | Deliverable | Engine dependency / gate |
| --- | --- | --- |
| G01 | Audited panel/shot references, asset list, character proportions and documented inferred spaces | Existing capture/import tools; visual review must validate annotations |
| G02 | One finished hero character and opening interior, including matched close-up and wide shot | Existing tools for iteration; M01 for durable authoring; relevant M03/M04 features for final staging |
| G03 | A short playable opening with interaction, performance, captions and representative sound | G02; measured controller/collision/audio integration and save/reopen |
| G04 | Remaining depicted locations, characters, connecting routes and story performances | Approved G02 quality standard; M06/M07 when the content exceeds current scale limits |
| G05 | Reviewed panel-to-runtime captures and reproducible finished game build | No unresolved critical/major fidelity issues; gameplay/audio/accessibility checks; M10 for advertised engine support |

The first production benchmark must contain representative hero art, lighting,
weather, animation and audio. Proxy-only frame rates cannot forecast its cost.
Image metrics may identify drift; character likeness and narrative staging also
require visual review. Voice acting, unseen geometry and free-camera angles are
adaptation decisions, not evidence of literal identity with printed panels.

## Measurements and release rules

Before a performance gate, record the scene revision, resolution, quality settings,
hardware/driver, warmup, camera route, duration, CPU/GPU percentiles and memory.
The earlier 1080p/60 FPS engine target and a game's higher-resolution target are
separate proposed workloads, not measured guarantees. Choose and freeze the
representative game's target before optimizing it; record any later scope change.

Retain these proposed acceptance checks from the baseline: 30-minute travel/edit
runs, bounded memory after warmup, safe teleport recovery, save fault injection,
visible window resize/presentation and clean shutdown. M10 extends endurance to
an overnight run and pins the supported platform/driver matrix. Broad x86-64
support requires its own runner and evidence.

For each milestone, record an owner/responsibility, status, artifact identity,
commands, fixture revisions, measurements and known exclusions. Art direction,
character/environment production, animation/audio, engine implementation and QA
are distinct responsibilities; this roadmap does not imply staffing exists.

Publish a completion claim only after its acceptance evidence passes. Preserve
historical reports and identify which build they tested. Regenerate and verify the
SDK when implementation changes ship. The compatibility profile must continue to
state its supported subset; neither a finite test count nor this roadmap establishes
universal USD support or comic-to-game visual identity.

## Scheduling

M01–M03 are complete for their declared profiles. The next acceptance gate is
**M04: freeze a representative lighting/camera workload and approve its target**.
The native SDL3 migration proceeds as a separate dependency change. G01/G02 can progress
alongside engine work once the reference scope is established. M04 visual fixtures
can also begin before all authoring work is finished.

Calendar estimates remain uncommitted until M01 and the first finished reference
scene establish measured throughput, staffing and review capacity. Reforecast at
each completed milestone using remaining fixture/asset counts and observed effort.
The full roadmap is not a single implementation batch; each gate produces a usable,
tested increment.
