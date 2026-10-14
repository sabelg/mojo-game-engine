# Native Mojo GPU physics proofs — G01, G02, G03a/b/c and G04a/b

GPU simulation is the primary Atlas physics target. This isolated experimental
module is the first actual GPU implementation: fixed SoA state, independent
sphere/box-body integration, finite error/status kernels and whole-batch commit.
The unchanged CPU R01/R02a modules are the correctness oracle. G02 now supplies
persistent GPU body storage, generation-checked handles and ordered lifecycle
commands; see [G02 lifecycle](LIFECYCLE.md). G03a adds GPU-owned spheres, bounded
AABB candidates and sphere/sphere contact geometry; see [G03a detection](CONTACTS.md).
G03b adds finite oriented boxes and sphere/box contacts; see [G03b geometry](OBSTACLES.md).
G03c adds GPU one-point pair/feature history and new/persistent/ended observations;
see [G03c history](PERSISTENCE.md).
G04a adds bounded serial GPU normal response and split COM penetration recovery;
see [G04a response](NORMAL_RESPONSE.md). Planes/meshes, box/box response, scalable broad phase, general persistent
multi-point manifolds, joints and CCD remain unimplemented. G04b adds a cold circular-cone
friction block with one uniform coefficient; see [G04b friction](FRICTION.md).
The opt-in [stability correction](STABILITY.md) projects privately before fresh
velocity constraints; original G04a/b order and baselines remain available.

The qualified deployment target is NVIDIA GB10/Linux ARM64. The host owner
rejects other device names rather than silently falling back to CPU. Float64 is
an initial correctness profile, not the production performance architecture;
Float32 needs separate range/error and performance qualification.

## Recommended opt-in experimental GPU review

Use `experimental.physics_gpu.recommended.GpuPhysicsResponse` for new experimental
response callers. It selects the qualified `GpuStableFrictionResponse`: private
COM projection, fresh contacts and cold velocity solve before one final commit.
This recommendation applies to the experimental review/examples only. The ordinary
`mojo_game` API/SDK and Yo Frankie campaign/default executable stay unchanged.

```mojo
from experimental.physics_gpu.recommended import GpuPhysicsResponse
var physics=GpuPhysicsResponse()
# Lifecycle/shapes: physics.response.normal.history.world
```

```sh
python3 scripts/qualify-gpu-physics.py test --slot-confirmed --build
python3 scripts/qualify-gpu-physics.py packaged --slot-confirmed --build
python3 scripts/qualify-gpu-physics.py demo --slot-confirmed --build
```

The new game-owned `gpu_physics_recommended.mojo` is the recommended response
review. It preserves the low/high-friction scene and uses one 60-Hz physics step
for each of 60 rendered frames. All 120 body states/count/energy reports match
independent post-render CPU replay; the original 0.001 m/s surface-slip gate and
zero Vulkan-error gate pass. Four preview snapshots are real rendered frames
0/20/40/59, distinct from numerical suite output. Receipts and snapshots use
`physics-gpu-recommended` / `frankie-gpu-recommended` names and do not overwrite
old evidence.

Midpoint slop still prevents exact material-surface sticking. Integration/contact
timing and cold incline numerical dissipation still require explicit timestep
quality choices; see [STABILITY.md](STABILITY.md). This remains serial Float64,
one friction coefficient, no warm start/new shapes or production performance claim.

Original G01/G02/G03 examples and G04a normal review remain named historical
qualification modes. Original G04b APIs, `gpu_friction_review.mojo` and its four
240-Hz substeps remain a regression baseline, and the original 60-Hz failure is
retained separately. They are not the recommended path for new response examples.

## Environment and legacy qualification commands

Atlas's locked Mojo `1.2.0.dev2026092905` has no `std.gpu`. Its compiler diagnostic
directs GPU imports to MAX. The official matching `max-core 26.7.0.dev2026092905`
requires exactly that Mojo compiler and supplies `max.gpu` and the host runtime.
It is isolated in `.deps/physics-gpu-g01`; Atlas's working environment, main
lockfile and H3 environment remain unchanged. MAX core/compiler carry the
upstream Modular license recorded in package metadata. No PhysX/Jolt runtime
or upstream physics implementation is used.

The separate environment manifest pins:

```toml
[dependencies]
mojo = "==1.2.0.dev2026092905"
max-core = "==26.7.0.dev2026092905"
```

Use the existing isolated environment. On another fresh checkout, reproduce the
manifest under `.deps/physics-gpu-g01/pixi.toml` with the official MAX-nightly and
conda-forge channels, Linux ARM64, then explicitly install that manifest. The
qualification launcher performs no installation or upgrade. Obtain the exclusive
CPU/GPU slot before executing; do not run alongside H3:

```sh
python3 scripts/qualify-physics-gpu.py capability --slot-confirmed
python3 scripts/qualify-physics-gpu.py test --slot-confirmed
python3 scripts/qualify-physics-gpu.py demo --slot-confirmed
```

Add `--build` to recompile the selected target. Changed source/artifact hashes
also trigger a rebuild. Commands use one compiler thread, 180-second compile,
10-second capability and 30-second numerical/render bounds with a 32 GiB
available-memory reserve and sampled temperature observation. No thermal cutoff,
hardware control, driver change, benchmark or H3 launcher is involved.

## Device contract and precision

SoA has 23 Float64 fields with capacity 256 and per-field tail canaries. Two
state buffers allow candidate integration and whole-batch rejection; a bounded
integer status reduction precedes commit. There are no floating-point atomics or
cross-body constraints. Step status is explicitly observed on the host. Force
commands and integration execute on device; full state returns only for explicit
diagnostic snapshots. G02 adds experimental generation-checked body handles; G03a adds shape handles.

The integrator retains R02a's dt/substep/iteration/angular limits and force lifetime.
The locked standard library does not support NVIDIA Float64 `cos`, so the device
rotation increment uses fixed double-precision sine/cosine polynomials for
`angle/2 <= .125`, through degrees 11/12. Truncation is below `3e-22` on that
interval; floating-point rounding is checked against the independent CPU oracle.
It does not cast angular math to Float32 or modify the CPU implementation.

Predeclared gates: component error `1e-8*(1+abs(reference))`, rotated-basis error
`1e-7` and quaternion norm error `1e-10`. Original anisotropic energy bounds at
30/60/120 Hz remain `2e-4/5e-5/1.5e-5`, with momentum-component bound `5e-9`.
Same-device/build replay and body-permutation fixtures are exact for this
independent-body kernel. Cross-CPU/GPU/compiler bitwise determinism is not claimed.

The game-owned `games/yo-frankie/examples/gpu_physics_review.mojo` runs actual
legacy `Game.step` while sixteen orange bodies use GPU integration. It runs for
60 frames and compares the CPU oracle after rendering. Each frame exports only
seven pose values per active GPU body (896-byte payload, 912-byte guarded output
buffer) before existing Vulkan upload. This is GPU compute with staged render
snapshots, not direct CUDA–Vulkan sharing. Normal campaign/assets/saves and the
existing CPU review are preserved. Output is `build/frankie-gpu-physics-demo.bmp`
and `build/frankie-gpu-physics-rendered.json` in the game directory.

Explicit buffers total approximately 108 KiB at the 256-body maximum, including
full pose output; they stay under the 16 MiB cap. Host mappings, driver/runtime
context and compiler allocations are additional and measured by qualification.
No throughput/FPS result is inferred from test wall times. GPU kernels have
finite internal loops; terminating a host process alone is not a guarantee that
already executing device work stops immediately.

This module is deliberately outside the ordinary `mojo_game` compiled API and
source SDK until its GPU dependency/packaging contract is reviewed. Its launcher
records separate source and executable fingerprints. See
[the GPU-primary roadmap](../../docs/PHYSICS_ROADMAP.md) for contacts, scheduling,
islands, interop and subsequent release gates.

## October 12, 2026 qualification

All three documented launcher modes passed on NVIDIA GB10. Numerical coverage
includes tail/canary and 0–256 capacity cases, near-angular-limit rotation,
same-build replay/body permutation, mixed-batch rollback, nonfinite command and
invalid-count rejection, and two-second force/torque/gravity and torque-free
anisotropic trajectories at 30/60/120 Hz. The GPU game review performed live
stepping for 16 bodies/60 frames, compared the CPU reference afterwards and
reported zero Vulkan validation errors. The launcher uses Atlas's existing
Vulkan wrapper so architecture-matched validation layers are found.

Maximum measured normalized component/frame/norm differences in the anisotropic
fixtures were `6.5043188e-15 / 1.6729631e-14 / 2.2204461e-16`. Energy and momentum
gates retained their original budgets. No throughput, Float32, other hardware,
contacts or direct interop qualification is inferred.

Receipts: `build/physics-g01/{capability,test,demo}-qualification.json`.
Detailed rollback/failure/final records:
`/home/user/Documents/Codex/2026-10-12/task/physics-g01-20261012`.

## G03a sphere detection checkpoint

Source and precompiled-API tests passed on GB10 against an independent CPU
geometry oracle: 64 owned spheres, at most 2,016 canonical unordered pairs,
transactional attach/detach/reshape, explicit output overflow and body/shape reuse
invalidation. G01/G02 regressions passed unchanged. A live eight-sphere/60-frame
Yo Frankie review passed post-render oracle comparison and Vulkan validation.
This is detection only with a fixed all-pairs prototype; it does not apply
response or claim a scalable broad phase. See [CONTACTS.md](CONTACTS.md) for exact
bounds, memory/transfer accounting, commands, evidence and remaining gates.


The G03 guard follow-up also passed source/precompiled-API fixtures for foreign
shape namespaces, revision exhaustion and final-generation retirement through
detach and body-orphan cleanup. Failed commands preserve published state, and
retired slots cannot resurrect through shape/body reuse. Only tests and coverage
documentation changed; see CONTACTS.md for named fixtures and the updated receipt.


## G03b floor and obstacle geometry checkpoint

Sphere/oriented-box detection passed source and precompiled API against an
independent matrix/eight-corner/six-face CPU oracle, analytic transformed
face/edge/corner/inside cases and metamorphic ordering/rotation checks. A short
rotating dynamic-box trajectory, box lifecycle/revision/reuse, invalid descriptor,
kind and overflow fixtures passed. G01/G02 and G03a source/precompiled regression
gates remain unchanged. The opt-in 60-frame Yo Frankie floor/ramp/obstacle review
passed CPU-oracle and Vulkan validation with three boxes and five GPU spheres.
See [OBSTACLES.md](OBSTACLES.md) for exact supported pairs, conventions and evidence.
Box/box and planes remain unimplemented; G04a separately supplies bounded normal response.


## G03c one-point history checkpoint

GPU history/matching and atomic publication passed source/precompiled API,
independent reference and analytic sequences for continuity, separation/recontact,
revisions/features/ambiguity, removal/reuse, overflow and counter exhaustion.
All G01/G02/G03a/b regression gates remain unchanged. The live 60-frame review
shows new/persistent/ended contacts; every recorded frame matched the CPU reference
after rendering, with zero Vulkan validation errors. This is one point per pair,
without impulse reuse, general multi-point manifolds or response. See
[PERSISTENCE.md](PERSISTENCE.md) for matching, transaction scope and remaining work.


## G04a normal response checkpoint

Source and precompiled-API GPU tests passed analytic momentum/energy laws and an
independent matrix-based reference for rotational effective mass, restitution,
shared-body constraints, shallow recovery and 30/60/120/240 Hz support. Failure
fixtures preserve authoritative body/force/history state. The original rotated
tangency is explicitly covered with exact bits and strict separation ≤0; the
independent CPU matrix was repaired to preserve quarter-turn/inverse cancellation.
GPU geometry and earlier numerical gates are unchanged. G01/G02 and G03a/b/c
source/precompiled regressions passed. The 60-frame game review passed physical
rebounds/velocity reversal, post-render CPU replay and zero Vulkan errors.

This is a one-thread GPU contact sweep with at most 64 contacts, cold impulses
and COM-only split projection. It does not qualify parallel solver throughput,
friction, warm start, arbitrary deep scenes or a complete G04 release. See
[NORMAL_RESPONSE.md](NORMAL_RESPONSE.md) for laws, rejection/profile limits,
transaction scope, exact boundary decision, memory and evidence.


## G04b one-coefficient friction checkpoint

Source and precompiled-API GPU tests passed circular friction-cone, closed-form
impulse/energy, anisotropic block/KKT, rotation/basis, incline rolling/slip, shared
body, four-timestep trajectory, 64-contact capacity and rollback checks. The CPU
reference uses independent spectral diagonalization and KKT stopping; constructed
analytic cases check both implementations. G01–G04a source/compiled regressions
and original exact boundary gates remain unchanged.

The 60-frame two-world Yo Frankie review contrasts mu 0.02 and 0.8, with four
240-Hz physics substeps per frame. All frame states/reports match post-render CPU
replay and Vulkan validation reports zero errors. The earlier 60-Hz review
failed its surface-slip gate because G04a COM projection follows the velocity
solve; that limit and the predicted timestep error remain documented. The
qualified review keeps the original gate. This is cold serial friction with one
static/kinetic coefficient, not exact post-projection surface sticking, separate
static/dynamic materials, warm starting or parallel solver performance. See
[FRICTION.md](FRICTION.md) for the law, verified limits, failures and evidence.


## G04 stability correction checkpoint

The separately qualified `GpuStableFrictionResponse` removes G04b's timestep-squared
anchor-slip bias by projecting privately, rebuilding contacts and solving
velocities at the projected pose before one final commit. The original 60-Hz
scene passes its unchanged 0.001 m/s gate, without substeps. Original G04a/b code,
the failing 60-Hz counterexample and passing 240-Hz review are preserved.

Source/precompiled tests passed analytic point-velocity/impulse/work laws,
four-timestep refinement, five-second support, inclined rolling/sliding, fresh
rotating geometry, shared contacts, full capacity and transaction failures.
Original G01–G04 gates remain unchanged. Material surface slip from midpoint
slop, first-order integration/contact timing and numerical incline constraint
dissipation remain explicit limits; exact sticking or general conservation is
not claimed. See [STABILITY.md](STABILITY.md) for the API, diagnosis and evidence.


Recommended experimental integration receipts:
`build/physics-gpu-recommended/{test,packaged,demo}-qualification.json` and
`games/yo-frankie/build/frankie-gpu-recommended-rendered.json`.
Final fingerprints, rendered versus numerical evidence, Library animation,
preserved baselines and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-gpu-recommended-20261013/verification.json`.

G05a now supplies a separate bounded `islands.GpuContactIslands` owner for resident
GPU contact components. Fixed anchors do not merge dynamic islands. Source and
precompiled graph/identity/capacity/publication tests and the split/rejoin/reuse
diagnostic are documented in [ISLANDS.md](ISLANDS.md). The recommended response
owner is unchanged; sleep, warm starting and scheduling remain future work.

G05b adds `sleep.GpuSleepingPhysics`, a separate opt-in conservative GPU island
sleep/wake owner and default-off whole-world idle gate. See [SLEEP.md](SLEEP.md)
for exact-zero activity, supported dwell, mutation/wake, failure scope and counted
work semantics. Recommended response remains unchanged; no per-island skip or
performance claim is made.


A separate detection-only `box_box.GpuBoxBoxDetection` now adds oriented box/box
SAT and bounded face/edge contact geometry, with source/precompiled actual GPU
checks and a six-edit diagnostic. See [BOX_BOX.md](BOX_BOX.md) for the nine-point
bound, signed depth, numeric conditioning and publication scope. These patches
do not enter recommended response, one-point history, island or sleep owners;
box stacking and multipoint solving remain unqualified.


A separate `box_response.GpuBoxResponse` now provides bounded multi-point box-only
response with <=4 selected points per patch, rank-aware normal blocks and the
existing Coulomb law after private projection/fresh geometry. See
[BOX_RESPONSE.md](BOX_RESPONSE.md) for the preserved 30-Hz/64-sweep three-cube
counterexample, distinct explicit96 policy and extra cost, physical gates and
qualification domain. This owner does not replace the recommended sphere paths
or qualify general stacks, persistent manifolds, sleep or parallel throughput.
