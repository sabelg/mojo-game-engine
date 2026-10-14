# Atlas GPU physics roadmap — native Mojo, GB10 first

**GPU-resident physics is the primary product target and the first priority.**
Use native Mojo GPU kernels for simulation on NVIDIA GB10. Keep the validated
CPU implementation as a numerical oracle, diagnostic path and test harness;
do not grow a CPU product solver first and defer GPU work to an optional port.
This supersedes the earlier CPU-first/optional-GPU roadmap. G01 integration and G02 body lifecycle now have qualified GPU proofs;
G03a sphere ownership/detection, G03b sphere/oriented-box geometry and G03c
one-point contact history are qualified. G04a now qualifies bounded serial GPU
normal response, restitution and split COM penetration recovery.
G04b now qualifies cold one-coefficient circular-cone friction on that serial
solver, with explicit limits from subsequent COM projection.
An opt-in position-first stability correction is now qualified against the
retained original G04b counterexample and original numerical gates.
G05a now qualifies bounded GPU contact-island construction.
G05b now qualifies conservative island sleep/wake state and an opt-in whole-world
idle gate. A separate detection-only box/box owner now qualifies bounded oriented
contact geometry; multipoint response/history adoption remains future work. Broader sleep, compaction/filter work and G06–G09 remain planned and unimplemented. No time, speedup or PhysX/Jolt parity is promised.

## Long-term success criteria — state-of-the-art library

The product ambition is a state-of-the-art GPU-first native Mojo physics
library. G01–G04b are qualified foundations for that ambition; their small body,
shape and scene limits do not define the final scope. The criteria below are
future acceptance work. Today's supported and qualified capabilities remain
listed separately in the next section, with their exact limits and evidence.
No production-scale performance, full G03/G04 solver or PhysX/Jolt parity is
currently qualified.

- **Stability and conservation:** publish the supported unit/scale, mass/inertia,
  timestep and iteration ranges. Test long-duration drift and dt/iteration
  convergence, isolated-system linear/angular momentum, torque-free rotation
  and energy error. State the physical conditions for each invariant: external
  force/work, static supports, damping, friction and restitution change the
  appropriate momentum/energy accounting. Add adversarial high-ratio and
  near-degenerate fixtures as their support is qualified; reject inputs outside
  declared limits. Keep independent analytic/CPU references and predeclared
  numerical budgets rather than deriving budgets from a failing run.
- **Robust contacts and friction:** qualify transformed face/edge/corner cases,
  touching and deep/near-degenerate overlap, stable normal/witness conventions,
  manifold persistence/invalidation and accurate shape/body identity. Test
  non-attractive normal response, restitution/energy consistency, penetration
  recovery, resting stacks, incline stick/slip and supported Coulomb-friction
  behaviour. Expose capacity/iteration exhaustion and include solver residual,
  penetration and drift measures alongside completion status.
- **GPU scaling and execution cost:** qualify a measured range of sparse/dense
  body and contact workloads, varying island sizes and constraint colour counts.
  Record broad/narrow phase, graph/scheduling, solve, integration and publication
  costs; kernel launches, synchronization, transfer bytes/directions, memory
  peaks and compute/render contention are part of the result. Measure complete
  simulation/frame latency distributions as well as component timings. Declare
  precision, capacities, overload behaviour and supported hardware; establish
  numerical ranges before optimizing Float32 or asynchronous execution. Set
  scale/performance targets with the chosen workloads before benchmarking; no
  unmeasured body-count, FPS or speedup target is claimed as achieved.
- **Reproducibility and maintainability:** retain versioned scene definitions,
  initial conditions/seeds, expected results, exact source/artifact hashes,
  compiler/runtime/driver/device/settings and commands. Define replay and
  ordering guarantees by supported configuration; report numerical tolerances
  explicitly where bitwise agreement is not supported. Make source and packaged
  API checks, rollback/overflow/lifetime tests and regression scenes repeatable.
  Experimental APIs mature through documented compatibility and release gates.
- **Demanding benchmark scenes beyond Yo Frankie:** maintain a separate,
  versioned correctness/benchmark suite spanning dense piles and tall stacks,
  mixed shapes/size/mass ratios, contact-rich frictional motion, large connected
  islands, fast impacts and rapid insertion/removal. Add joint chains and
  articulated scenes, terrain/mesh interaction and thin-obstacle CCD cases when
  the corresponding feature is implemented and qualified. Yo Frankie remains
  an integration review; benchmark conclusions require the separate workloads,
  quality measurements, repeated sampling protocol and published limits.
- **Fair PhysX/Jolt comparisons:** use exact released/source revisions and
  officially supported configurations for each comparator. Publish build flags,
  CPU/GPU/backend choice, hardware/resource budgets, scene data, supported
  features, timestep/substeps, precision where selectable and solver-quality
  settings. Compare equivalent work and comparable measured quality; label
  implementation/configuration differences and unavailable features rather than
  infer parity from timing alone. Report both correctness/stability and latency,
  throughput/memory results with the sampling protocol. Add external software
  only in a separately scoped comparison stage after license/provenance review.
- **Staged advanced capabilities:** joints, islands/sleep, terrain/queries,
  selective CCD and render interoperability follow their roadmap dependencies.
  Broader articulation/compound/hull support and other advanced physics may
  extend later milestones after their requirements and budgets are reviewed.
  They are aspirations, not current capability or parity promises. Separate
  algorithmic correctness, integration, scale and API release qualification.

These criteria need no benchmark installation or execution for this roadmap
clarification. Future long-duration and comparative runs require their own
approved finite workload/resource plan; the current exclusive-slot, one-thread
build, 32 GiB reserve and normal application settings remain unchanged.


## What is verified today

| Component | Verified status | Limit |
| --- | --- | --- |
| Bounded box-only multi-point response | Separate source/precompiled actual GPU rank-aware normal/Coulomb response, independent geometry/elimination/spectral references, fixed contract/physical gates, two-second rest and motion refinement, and short response diagnostic. | <=16 patches/64 selected points, serial cold solve; centered three-cube 30-Hz/64-sweep failure retained. Explicit96 passes that scene at66 sweeps with unchanged gates and extra work; no general stable-stack or mixed/sleep/history adoption claim. |
| Box/box contact geometry | Separate source/precompiled actual GB10 SAT, face clipping and edge witnesses passed independent corner/constructive/Gram references, seeded near-degenerate/metamorphic, lifecycle/invalid/capacity/rollback tests and six-edit detection diagnostic. | At most nine points per patch; binary64 input/intersection conditioning limits are explicit. No box response, persistent manifold, island/sleep adoption or stacking-readiness claim. |
| G05b conservative sleep/wake | Source/precompiled GPU eligibility, generation-safe island wake and opt-in whole-world idle skip passed rational/CPU state-machine, activity/support/lifecycle, rollback/counter and active-baseline checks; short device events diagnostic passed. | Exact-zero motion and bounded representation pose stability; zero gravity or vertical shallow static-support paths. Whole-world gate defaults off; no per-island skip, broad incline/pile sleep or performance claim. |
| G05a GPU contact islands | Source/precompiled actual GB10 min-root components matched independent CPU geometry/flood fill through topology, identity, permutation, capacity and rollback checks; five-step edit diagnostic passed. | Serial GPU metadata construction over 256 body slots/64 shapes/2,016 contacts; fixed anchors do not merge dynamic islands. Separate experimental owner; no sleep, warm start, solver scheduling or performance claim. |
| R01 mass/inertia and impulses | Seven CPU numerical groups passed through source and compiled API, with unchanged legacy regressions. | CPU qualification; not a GPU kernel. |
| R02a single-body integration | Force/torque, normalized pose, bounded angular midpoint and transactional rejection passed CPU numerical/API/legacy checks in seventeen bounded stages. | CPU oracle; no body world or contacts. |
| Recommended experimental integration | Source/precompiled selection of `GpuStableFrictionResponse` and separate 60-frame Yo Frankie live review passed independent replay, original 60-Hz slip gate and zero Vulkan errors. | `recommended.GpuPhysicsResponse` is opt-in for experimental callers/reviews. Original APIs, counterexample and 240-Hz baseline stay explicit. Ordinary SDK/campaign adoption, exact sticking and timestep/dissipation limits remain pending. |
| G04 stability correction | Private projection then fresh cold velocity constraints passed source/precompiled analytic/reference, original-scene 60-Hz gate, four-timestep, five-second, incline, rotating/shared/capacity and rollback checks. Original G01–G04 regressions passed. | Separate opt-in owner; original code/baselines retained. Midpoint slop prevents exact surface sticking; integration timing and cold incline dissipation still require explicit quality/refinement choices. Newly created contacts during projection reject. |
| G04b GPU one-coefficient friction | Source/precompiled GB10 analytic, spectral/KKT reference, cone, shared-body, 64-contact and rollback checks passed; four timestep trajectories quantify surface slip after COM projection. 60-frame low/high comparison at 240-Hz physics passed all CPU frame states and zero Vulkan errors. | Cold one-thread GPU circular tangent blocks, one uniform static/kinetic coefficient. Sticking is at the frozen velocity contact point; exact post-projection surface no-slip, separate materials, warm start and parallel throughput remain unqualified. |
| G04a GPU normal response | Source/precompiled GB10 analytic and independent matrix-reference tests passed for restitution/rotational effective mass, shared bodies, penetration, support and transaction failures. 60 live frames passed CPU replay, physical rebounds and zero Vulkan errors. G01–G03 regressions passed. | One GPU thread, canonical PGS, ≤64 contacts, cold impulses, COM-only split projection, admitted ranges and explicit energy/convergence/post-detection rejection. No parallel throughput, friction, warm start or complete G04 claim. |
| G03c GPU one-point history | Source/precompiled GPU history/reference/analytic lifecycle and publication tests passed, including 2,016 contacts/4,032 events and counter exhaustion. All 60 live review frames matched independent reference; zero Vulkan validation errors. | One current point per supported pair/region, exact generation/revision identity, conservative feature/normal/ambiguity resets. No general multi-point manifold, stable local anchor or impulse reuse. |
| G03b GPU sphere/OBB geometry | Source/precompiled GPU tests passed independent matrix/corner/six-face, analytic/metamorphic, dynamic rotated-box and lifecycle/error/capacity fixtures; three boxes/five spheres over 60 live Yo Frankie frames passed CPU oracle and zero Vulkan validation errors. | Sphere/sphere and sphere/OBB only; finite boxes for floors/ramps/obstacles, one contact per pair. Box/box and planes excluded; no response or scalable broad phase. |
| G03a GPU sphere detection | Source and precompiled-API GB10 tests matched an independent CPU oracle, with 64 owned spheres, complete ordered AABB pairs, one sphere contact per pair, transactional shapes, explicit overflow, foreign namespaces and counter-exhaustion retirement. Eight live spheres/60 Yo Frankie frames passed with zero Vulkan validation errors. | Detection only; fixed all-pairs prototype, no response, other geometry, persistent manifolds or scalable broad phase. |
| G02 GPU body lifecycle | Passed source and precompiled-API GPU lifecycle/atomicity/residency tests, unchanged G01 numerical regressions and a 16-body/60-frame live Yo Frankie remove/reuse/stale-update review. | GPU body registry only; fixed slots, no compaction or performance claim. G03 supplies the separate sphere/box registry. |
| G01 GPU integration proof | Passed on NVIDIA GB10: real Float64 kernel launch, 0–256-body SoA differential/replay/tail/rollback checks, 30/60/120 Hz trajectories and 16 live GPU bodies over 60 Yo Frankie frames with zero Vulkan validation errors. | Independent bodies only; no contacts or direct CUDA–Vulkan sharing. Experimental source is isolated from the normal compiled API/SDK. |
| Atlas/Yo Frankie integration | Root native API/build and 264-file SDK refreshed. Game CPU suites, physics review and original-level/window renders passed with matching fingerprints and zero Vulkan validation errors. | Physics review bodies were CPU-integrated; Vulkan rendering is not GPU physics. |

Preserve `MassProperties3D`, `RigidBody3D` and their tests. Their SI/COM conventions,
impulse semantics and force lifetime define the initial GPU reference contract.
The qualified R02a limits are `0 < dt <= 0.25`, default 1/120-second ceiling,
explicit ceiling at most 1/30, at most 32 substeps, and angular midpoint at most
16 iterations/0.25 radians per substep. Failed steps retain state/accumulators.
General angular energy is approximate; retain the existing measured anisotropic
fixtures and their predeclared bounds rather than replacing them with visual checks.

Legacy `Physics2D`, frictionless sphere `Body3D`/`Physics3D`, capsule/box/triangle
queries, character controller, navigation and Yo Frankie campaign remain separate
implemented systems. Reuse their tested math/query contracts and preserve their
behaviour; they do not supply a GPU rigid-body solver. No external PhysX/Jolt runtime
or translated upstream implementation is introduced.

## Deployment and inspected capability boundary

Initial deployment is this Linux ARM64 ThinkStation PGX/GB10, with Atlas's locked
Mojo `1.2.0.dev2026092905` as the starting compiler. NVIDIA lists GB10 as CUDA
compute capability 12.1 in its [official table](https://developer.nvidia.com/cuda/gpus).
Record the actual runtime/driver/device target at qualification; do not assume
support from a graphics test. Other NVIDIA GPUs, AMD, Windows and multi-GPU
execution need separate qualification. GB10-specific code must be isolated.

Before G01, inspection found no Mojo GPU context/kernel code in Atlas. The installed Mojo
compiler includes `libAsyncRTRuntimeGlobals.so`; this alone does not verify GPU
launch support or the required host API. The local `mojo-gpu-puzzles` checkout
uses older `gpu.host` examples and a different toolchain. Current
[Modular GPU examples](https://github.com/modular/mojo-gpu-puzzles/blob/main/problems/p02/p02.mojo)
use `max.gpu.host.DeviceContext`, device buffers and queued launches. G01 resolved this with official `max-core 26.7.0.dev2026092905`, whose dependency
requires exactly the locked Mojo compiler, in a separate `.deps/physics-gpu-g01`
environment. Its `max.gpu.host.DeviceContext` and `max.gpu` kernels compiled and
ran on GB10. The main Atlas lock/environment and H3 environment were preserved. Do not copy the puzzle
environment, upgrade global tools or silently relabel an untested compiler.

Atlas's `native/mojo/runtime.mojo` creates/maps Vulkan buffers; `instances_upload`
writes CPU-generated instance matrices after a frame wait. `uploads.mojo` has
staging-copy batches, fences and visibility barriers; `frames.mojo` manages frame
fences. Inspection found no CUDA imports, external-memory/semaphore export,
device-UUID matching or `vkCmdDispatch` in that runtime. Existing Vulkan uploads
are useful for a small staged demo, not an existing CUDA–Vulkan bridge.

NVIDIA documents [CUDA–Vulkan external-resource interoperability](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/graphics-interop.html):
resources must be exported/imported compatibly on the matching device, with
explicit synchronization and correct lifetime. Capability support and Mojo's
imported-pointer/stream integration remain unverified here. GB10 shared DRAM
does not turn an arbitrary Vulkan or CUDA pointer into a safe shared resource;
allocation accessibility and execution ordering still matter. See NVIDIA's
[GB10 memory guidance](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html) and
[platform memory limitations](https://docs.nvidia.com/dgx/dgx-spark-porting-guide/porting/cuda.html).

## Proposed GPU architecture

G01 implements bounded integration and staged poses. G02 adds device-resident
body liveness/generations and ordered transactional commands; no host registry
allocates slots or validates stale identity. G03a adds generation/revision-checked
sphere ownership and GPU detection; G03b adds oriented boxes and sphere/box geometry. Other collider types, constraints, compaction
and later scheduling remain design decisions to validate.

- **Resident SoA state:** separate device arrays for COM position, quaternion,
  linear/angular velocity, mass/inverse mass, principal inertia/inverses,
  accumulated force/torque, body type, validity/status and revision. Start with
  Float64 to compare R01/R02a faithfully; qualify Float32 as a separate production
  profile after this proof. No FP16/mixed-precision solver without error evidence.
- **Stable identity:** public body/shape handles are slot plus generation, never
  raw device indices. Keep handle-to-dense-index and reverse mappings, shape
  revisions/local poses and command epochs. Compaction changes dense indices,
  not identities. Contact/joint/event keys include generations/revisions.
- **Bounded ownership:** preallocate capacity-counted body, shape, pair, manifold,
  constraint, adjacency, event and scratch buffers. Capacity exhaustion returns
  an explicit error; never silently drop contacts. Add/remove and material/force
  commands are ordered at step boundaries. Reclaim storage only after in-flight
  compute/render consumers retire.
- **Staged publication:** keep current and candidate state plus per-body error
  codes and a bounded batch status. Device code reports errors instead of throwing
  host exceptions. Validate before commit; on any G01 body failure, reject the
  entire batch and retain current state/forces. Later world steps must also keep
  caches/events and render publication consistent with the committed epoch.
- **Kernel phase graph:** command validation → external force/velocity prediction
  → bounds/candidates → narrow phase/manifolds → constraints → corrected pose
  → sleep/active compaction → events/render snapshot. G01 only implements the
  independent-body subset. Preserve the R02a public API while separating internal
  velocity/pose phases when contacts require it; do not consume forces twice.
- **Race-free solver contract:** prefer deterministic constraint colouring with
  no shared dynamic body within a colour; solve colours in a fixed order with
  separate launches. Build stable keys and bounded adjacency/colour buffers.
  A colour overflow rejects the step until a qualified strategy exists. No
  floating-point atomic scatter into shared velocities in the reference profile.
  An alternative Jacobi contribution/gather solver requires its own convergence
  and ordered-reduction tests; GPU parallelism alone is not stability evidence.
- **Asynchronous boundary:** one compute stream/context initially, ordered kernels
  and explicit completion/error observation. Host command, diagnostic readback and
  render-snapshot buffers use bounded rings; do not read/reuse an in-flight slot.
  Later overlap needs events and backpressure, not a host wait after every body
  or stage. Kernel boundaries provide phase ordering; a block barrier is not a
  grid-wide barrier. See [CUDA asynchronous execution](https://docs.nvidia.com/cuda/cuda-programming-guide/02-basics/asynchronous-execution.html).

## Critical path and stage outcomes

**Real GPU batch integration → resident handles/commands → GPU contacts →
race-free response/friction → islands/sleep → scene coupling, joints and CCD.**
Rendering interop is a parallel integration gate after the first proof. GPU memory,
scheduling and transfer measurement are present from the start, not added at the end.

| Stage | GPU deliverable and acceptance | Yo Frankie demo / boundary |
| --- | --- | --- |
| G01 — qualified proof | Batched independent sphere/box integration on device, checked against unchanged R01/R02a CPU oracle; finite error/status and batch commit. | Small force/torque/free-fall arena, GPU-labelled receipt. No contacts; bounded pose readback to existing Vulkan renderer. |
| G02 — qualified body subset | Persistent device body state, active flags and UInt64 generations; GPU slot allocation and transactional ordered create/update/remove/set-force. Stale/range/foreign handles, generation retirement, capacity, GPU address residency and lifetime tests passed. | Live game review removes/reuses slot 3 and rejects its old update on GPU. Fixed slots; G03a adds sphere association/revisions. Dense compaction is future work. |
| G03 — geometry/history subset qualified | G03a/b/c: GPU shape ownership/revisions, AABBs and bounded supported-pair generation; sphere/sphere and sphere/oriented-box geometry compared with independent CPU, analytic and metamorphic fixtures. G03c adds GPU one-point history, lifetime IDs/ages and transactional new/persistent/ended events. Remaining: sphere/plane, oriented box/plane, box/box, general multi-point manifolds and scalable broad phase. | Qualified sphere review and floor/ramp/inside-edge obstacle overlays, box revision/reuse, rotated features and short dynamic-box trajectory. One-point continuity/invalidation and event review qualified; general multi-point manifolds remain pending. No response or impulse-reuse claim. |
| G04 — normal subset qualified | G04a: bounded serial GPU normal/restitution constraints and COM-only split projection qualified. G04b: cold one-coefficient circular-cone tangent blocks qualified with explicit post-projection slip limits. Remaining: parallel colour scheduling, warm starting, rotational position correction, separate static/dynamic material laws and broader frictional support. Verify pair momentum/energy, non-attraction, resting penetration, incline stick/slip, stacks and iteration/dt sensitivity. | Crate drop, small pile, bouncing spheres and incline. Predeclare supported mass/size ratios; no attractive or unbounded impulses. |
| G05 — island subset qualified | G05a: resident GPU connectivity, canonical generation-tagged roots, static-anchor policy, fresh identity/topology validation and atomic island publication qualified against independent CPU flood fill. G05b: conservative GPU dwell/sleep/wake with generation-safe old/new island propagation and an explicit idle gate. Remaining: broader sleep policy, per-island work skipping, active-list scan/compaction, filters/sensors and broader bounded events; future impulse/force/support-removal wake and index-remap tests. | Qualified five-step split/rejoin/root-reuse diagnostic. Supported-rest sleep/force/support-removal diagnostic qualified. Broader sleeping piles, sensor zones and solver scheduling remain future stages. Large islands and colour counts remain explicit budgets. |
| G06 | Distance joint, then hinge/limits in the same race-free constraint graph. Anchor/axis, drift, deletion, connected wake and dt/iteration tests. | Tether and gate. No articulation/ragdoll feature promise. |
| G07 | GPU static terrain/triangle contacts and query adapters for existing character/nav systems; upload immutable BVH/scene data and stream revisions safely. Bounded pushing/support/query response and nav invalidation. | Movable crate/platform review before authored-level opt-in. No second controller/nav system or full CPU-state download each tick. |
| G08 | Selective GPU casts and CCD for demonstrated tunnelling; bounded time-of-impact queues/advances and exhausted-budget behaviour. Test thin walls, initial overlap, fast pairs/rotation against fine-step oracle. | Fast projectile lane. Mesh CCD depends on G07; arbitrary hulls/compound shapes remain separate scope. |
| G09 | Release profile and measured scale: data layout, pair/colour hotspots, occupancy, kernel launch and sync cost, memory/event budgets and compute/render contention. | Agreed workload, exact compiler/device/settings and frame-time distribution; no invented FPS/body-count target. |

Joint, character and CCD priorities can branch after their G04/G05 dependencies;
do not delay useful GPU physics behind a broad CPU-only expansion. Keep initial
broad phase simple and complete; replace it only with measured workload evidence.

## Render integration gate

**G01 staged path:** upload initial state once, integrate on GPU, and copy back
only a small committed pose snapshot for the isolated demo. Wait for completion
before the existing Vulkan upload. Mark receipts `GPU compute + staged Vulkan
upload`; do not claim zero-copy or a fully resident render path. CPU-oracle
comparison runs outside the timed render loop.

**Resident product path:** after G01, evaluate exportable Vulkan storage buffers,
CUDA-compatible mappings and explicit external semaphore/event ordering with
matching device UUIDs. GPU writes interpolated render matrices into a dedicated
per-frame output ring; simulation SoA remains private. Renderer waits for compute
publication; compute waits before reusing a render slot. Specify Vulkan access
visibility, queue ownership where required, FD ownership, imports/destruction and
device-loss handling. A Vulkan fence or CUDA completion alone does not order the
other API. Confirm whether the locked Mojo host API can consume imported pointers
and wait/signal on the required stream; do not assume its allocator can adopt them.

Gate direct sharing on capability checks, alternating frame stress within a finite
budget, no torn/stale transforms, safe resize/removal/shutdown and Vulkan validation.
If direct sharing is unavailable, keep a bounded snapshot bridge with measured
cost and an honest deployment limit; simulation still stays on the GPU. Do not
replace Vulkan with a second renderer just to avoid this boundary.

## G01: qualified implementation and reproducible scope

1. After the parent confirms H3's safe GPU-slot release, resolve the locked Mojo
   GPU host API/runtime and GB10 target with a tiny allocate/launch/readback check.
   No driver/system update; any required dependency is official and project-local,
   preserving the original lockfile/rollback. Unsupported target/API is a blocker
   to report, not a reason to silently run CPU physics under a GPU label.
2. Add an isolated experimental GPU module and one differential test. Marshal
   checked CPU bodies into bounded SoA; use one body per thread, a provisional
   64-thread block and explicit tail guards. Implement finite integration/error
   status into candidate buffers, then a status/commit phase. No collision races,
   dynamic device allocation or borrowed safety controller from H3.
3. Start with Float64 and the exact reference substep/angular limits; test impulse
   setup, gravity, force, off-centre torque, sphere spin, rotated anisotropic boxes,
   fixed bodies, accumulator clearing and rejected-state retention. Stage initial
   impulses deterministically; later command queues must preserve that order.
4. Compare after one step and fixed two-second 30/60/120 Hz runs. Proposed
   predeclared differential gates for ordinary SI fixtures: each position,
   linear/angular velocity component within `1e-8 * (1 + abs(reference))`;
   rotated-basis distance at most `1e-7` (quaternion sign-independent); norm error
   at most `1e-10`. Retain CPU fixture energy bounds `2e-4/5e-5/1.5e-5` and
   momentum-component bound `5e-9` in their original fixtures. These GPU gates
   are proposed, not passed; failure triggers diagnosis/review, not automatic loosening.
5. Exercise counts `1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 256`, plus zero
   and rejected over-capacity requests, tail canaries and one invalid member in a
   mixed batch. Reorder bodies and compare by stable identity. Require exact
   status/fixed-body results; compare arithmetic numerically. Same-device/build
   repeated runs should match in this no-reduction kernel; cross-CPU/GPU or
   cross-compiler bitwise determinism is not promised.
6. Only after differential tests pass, add an opt-in game-owned 60-frame GPU
   review of at most 16 bodies using the staged snapshot path. Preserve campaign,
   assets/saves and CPU demo. Record actual compute device, kernel/backend,
   numeric profile, body/frame counts, readback bytes and Vulkan errors. CPU
   fallback must be explicit and cannot produce a passed GPU qualification receipt.

The implemented source is isolated in `experimental/physics_gpu`, with
`scripts/qualify-physics-gpu.py` and the game-owned
`games/yo-frankie/examples/gpu_physics_review.mojo`. This keeps the qualified
CPU API/SDK independent of the new GPU runtime dependency. The host/world API
remains experimental. Keep CPU modules unchanged
unless a separately reviewed pure-math extraction is required and all reference
tests are retained. No contacts, broad phase, joints, CCD, assets or campaign redesign
in G01. Float32 and general production-range guarantees follow separately.

### Accepted resource budget and qualification

- Exclusive physics slot only after parent confirmation; H3 pauses at its safe
  checkpoint. No concurrent H3/GPU test or benchmark.
- One compiler thread; initial compilation deadline 180 seconds, tiny capability
  check 10 seconds, numerical executable 30 seconds, optional 60-frame render
  30 seconds. Sequential stages; report any revised bound before launch.
- Capacity 256 bodies for the first proof; at most 240 external steps per body
  for a two-second run. R02a internal loops retain their existing hard limits.
- Explicit physics buffers, host staging and scratch capped at 16 MiB; runtime
  context/compiler overhead is additional and measured. Keep at least 32 GiB
  system `MemAvailable`; shared GPU allocations count against the same pool.
- Finite launches, process-group cleanup, sampled temperature/memory observation
  and no stress/soak/benchmark. A host timeout cannot guarantee cancellation of
  an already executing GPU kernel; finite kernel loops are required. No GPU reset,
  thermal/driver/firmware settings or H3 launcher edits. Retired diagnostic thermal
  cutoffs remain inactive.

H3's safe cleanup and slot release were confirmed before any kernel launch.
The matching runtime/API and Float64 G01 gates passed; direct CUDA–Vulkan sharing
remains a later interop gate. No test tolerance or resource bound was loosened.
The locked stdlib rejects NVIDIA Float64 `cos`; G01 uses bounded Float64 sine/
cosine polynomials for half-angles up to .125 instead of casting to Float32.
See the module README for their degree/error range and implementation limits.

Measured GPU anisotropic energy error at 30/60/120 Hz was
`3.8782449244e-5`, `9.6954460631e-6`, `2.4238510892e-6`. Maximum normalized
component difference from the CPU oracle was `6.5043188e-15`, frame error
`1.6729631e-14`, and quaternion norm error `2.2204461e-16` in these fixtures.
The game integrates sixteen bodies on GPU each frame, exports a seven-value pose
snapshot, and runs the CPU oracle only after rendering; it is not pose playback.
Only the existing game movement marker uses the preserved legacy CPU controller.
There is no claim of production Float32, throughput, complete GPU world physics
or full campaign parity.

The G02 body lifecycle checkpoint is complete. Current/scratch GPU address
stamps stayed stable through repeated steps, updates and slot reuse; body-state
buffers do not upload from host each frame. Source and precompiled API tests
covered FIFO semantics, whole-batch failure, stale/range/foreign handles, capacity,
generation exhaustion and scope cleanup. The live game review removed/reused a
slot at frame 20, rejected its old update at frame 21 and updated the replacement
at frame 35, with post-render CPU agreement and zero Vulkan validation errors.

Host checks command size, closed ownership and ordinary body factories; GPU
checks identity/liveness and command/state semantics. Logical commands are 216
bytes; a one-command input staging allocation is 248 bytes including guards.
Registry/pose snapshot buffers total 20,512 bytes. Actual DMA traffic is not
measured and no zero-copy claim is made. G02 uses fixed slots; there is no dense
compaction; its sphere registry is supplied separately by G03a. Mass/inertia
updates require remove/create.
See [G02 lifecycle/API](../experimental/physics_gpu/LIFECYCLE.md).

G03a is complete for owned sphere/sphere detection: 64 shapes, one per body,
canonical candidate/contact keys, transactional shape revisions and explicit
2,016-pair maximum/output overflow. Its independent CPU oracle, source/precompiled
API, unchanged G01/G02 regressions and eight-sphere/60-frame live game review
passed. It uses bounded all-pairs AABB filtering, not a scalable broad phase;
contacts never alter body state. See [G03a geometry/API](../experimental/physics_gpu/CONTACTS.md).

G03b now adds sphere/oriented-box contact geometry, with independently checked
transforms, face/edge/corner/inside normals, signed witnesses, box lifecycle and
finite mixed-shape capacity. The live game review shows finite floor, rotated
ramp and obstacle contacts. Unsupported box/box pairs are excluded rather than
counted as covered. See [G03b geometry/API](../experimental/physics_gpu/OBSTACLES.md).

G03c now supplies GPU one-point pair/feature history with generation/revision
matching, deterministic lifetime IDs/ages, conservative normal/ambiguity resets
and atomic cache/event publication. It is correspondence metadata, not a general
convex manifold or permission to reuse impulses. See
[G03c history/API](../experimental/physics_gpu/PERSISTENCE.md).

G04a is complete for bounded normal response: canonical serial GPU sweeps, cold
impulses, rotational effective mass/restitution, separate COM projection and whole
body-candidate publication. The original rotated exact tangency is retained in
strict signed-boundary fixtures; the independent CPU quaternion matrix was repaired
without changing GPU geometry or adding a contact epsilon. See
[G04a response/API](../experimental/physics_gpu/NORMAL_RESPONSE.md).

G04b is complete for bounded cold Coulomb friction, with independent analytic/
spectral/KKT checks and exact zero-friction G04a equivalence. The retained COM
projection changes the surface lever after the velocity solve; timestep tests
quantify that limit and the live review uses four 240-Hz substeps per frame.
See [G04b friction/API](../experimental/physics_gpu/FRICTION.md).

The stability investigation now qualifies an opt-in position-first owner which
removes the dt² anchor-slip bias and passes the original-scene 60-Hz gate without
substeps. It retains original code/baselines and measures remaining midpoint-slop,
integration-timing and incline-dissipation limits. See
[stability diagnosis/API](../experimental/physics_gpu/STABILITY.md).

The recommended experimental entrypoint/review now uses the corrected owner at
one 60-Hz physics step per frame, with independently replayed real Vulkan frames.
Original APIs, counterexample and 240-Hz regression stay unchanged. See the
[recommended review](../experimental/physics_gpu/README.md).

The recommended-integration checkpoint remains preserved; G05a advances only
contact connectivity. Scope ordinary-engine/
campaign adoption, more exact anchors/integration, parallel solving, broader frictional support/materials,
impulse reuse, geometry and manifold work separately. Physics priority changes
scheduling, not finite qualification.

## API stability, correctness and provenance

Preserve native Mojo SI/COM semantics and generation-checked ownership. New GPU
world/contact APIs remain experimental with explicit enqueue/completion/snapshot
semantics; host reads must identify a committed epoch. ECS/render/controller
authority and interpolation have one publication boundary. Keep diagnostic CPU
oracle execution explicit; avoid a silent per-frame CPU product solver.

Every stage requires CPU-oracle/analytic comparisons, lifecycle/error/capacity
fixtures and exact source/artifact/toolchain/device records. Add declared shader/
interop checks and actual GPU receipts when those paths exist. Preserve legacy
regressions, assets/saves, dirty work, lockfiles and rollback evidence. Source/SDK
and game fingerprints refresh only after actual implementation qualification;
this roadmap edit does not rebuild or repackage them. Profile compute, transfers,
synchronization and rendering separately before claiming speedup or scale.

PhysX/Jolt are architectural references, not dependencies or evidence of feature
parity. Any future source reuse needs exact revision and component license/notice
review; see [Jolt](https://github.com/jrouwe/JoltPhysics/blob/master/LICENSE) and
[PhysX](https://github.com/NVIDIA-Omniverse/PhysX/blob/main/LICENSE.md). Cloth,
fluids, vehicles, arbitrary compounds, articulations and multi-GPU simulation are
outside the current G01–G09 implementation scope; future expansion requires
separate requirements and qualification. No upstream physics implementation was copied.

Current evidence: R01 at `/home/user/Documents/Codex/2026-10-12/task/physics-r01-20261012`;
R02a at `/home/user/Documents/Codex/2026-10-12/task/physics-r02a-20261012/verification.json`;
Yo Frankie at `/home/user/Documents/Codex/2026-10-12/task/frankie-atlas-20261012/verification.json`.
See [game coverage](../games/yo-frankie/docs/ATLAS_PHYSICS_REFRESH.md). Those earlier receipts remain CPU-physics/render qualification. G01's actual GPU
receipts are `build/physics-g01/{capability,test,demo}-qualification.json`; game
output is `games/yo-frankie/build/frankie-gpu-physics-rendered.json`.
Consolidated commands, hashes, initial/final logs, observations and preservation
checks are under `/home/user/Documents/Codex/2026-10-12/task/physics-g01-20261012`.

G02 receipts: `build/physics-g02/{test,packaged,demo}-qualification.json`; game
receipt `games/yo-frankie/build/frankie-gpu-lifecycle-rendered.json`. Commands,
hashes, logs, rollback and preservation evidence are under
`/home/user/Documents/Codex/2026-10-12/task/physics-g02-20261012`.

G03a receipts: `build/physics-g03/{test,packaged,demo}-qualification.json`; game
receipt `games/yo-frankie/build/frankie-gpu-contacts-rendered.json`. Commands,
hashes, logs, rollback and preservation evidence are under
`/home/user/Documents/Codex/2026-10-12/task/physics-g03-20261012`.


G03 guard follow-up: foreign shape namespaces and UInt64 shape
generation/revision exhaustion now have source and precompiled-API GPU fixtures,
with exact rejection rollback and no retirement resurrection through body/shape
reuse. G01/G02 regressions passed unchanged; production code and numerical limits
remain unchanged. The existing game review remains the earlier G03a receipt.
Latest guard evidence:
`/home/user/Documents/Codex/2026-10-12/task/physics-g03-guards-20261012/verification.json`.


G03b receipts: `build/physics-g03b/{test,packaged,demo}-qualification.json`; game
receipt `games/yo-frankie/build/frankie-gpu-obstacles-rendered.json`. Current
commands, hashes, logs, rollback, Library preview and preservation/cleanup evidence:
`/home/user/Documents/Codex/2026-10-12/task/physics-g03b-20261012/verification.json`.


G03c receipts: `build/physics-g03c/{test,packaged,demo}-qualification.json`; game
receipt `games/yo-frankie/build/frankie-gpu-contact-history-rendered.json`. Current
commands, hashes, logs, rollback, preview and preservation/cleanup evidence:
`/home/user/Documents/Codex/2026-10-12/task/physics-g03c-20261012/verification.json`.


G04a receipts: `build/physics-g04a/{test,packaged,demo}-qualification.json`; game
receipt `games/yo-frankie/build/frankie-gpu-normal-response-rendered.json`. Exact
boundary bits, preserved initial failures/oracle rollback, sequential regressions,
preview and cleanup evidence:
`/home/user/Documents/Codex/2026-10-12/task/physics-g04a-20261013/verification.json`.


G04b receipts: `build/physics-g04b/{test,packaged,demo}-qualification.json`; game
receipt `games/yo-frankie/build/frankie-gpu-friction-rendered.json`. Preserved
60-Hz surface-slip failure, analytic timestep evidence, unchanged G01–G04a
regressions, Library preview, preservation and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-g04b-20261013/verification.json`.


G04 stability receipts: `build/physics-g04-stability/{test,packaged}-qualification.json`.
Original counterexample and 240-Hz baseline, analytic timestep/work measurements,
unchanged G01–G04 regressions, preservation and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-g04-stability-20261013/verification.json`.


Recommended experimental integration receipts:
`build/physics-gpu-recommended/{test,packaged,demo}-qualification.json`;
`games/yo-frankie/build/frankie-gpu-recommended-rendered.json`.
Rendered preview/source/packaged evidence, final G01–G04/stability regressions,
preservation and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-gpu-recommended-20261013/verification.json`.

Independent axis-angle math repair: the tiny-axis identity bug is corrected with
max-component normalization and explicit zero/non-finite semantics. This is a
bounded correctness checkpoint, with binary64 and GPU trig limits documented in
[the axis-angle API note](AXIS_ANGLE.md); it adds no physics feature. Source,
compiled CPU/device and affected engine/GPU regression evidence is recorded at
`build/axis-normalization-recovery/verification.json`. Original G04 60-Hz failures,
240-Hz baselines, recommended 60-Hz gate and numerical budgets remain unchanged.
The repair checkpoint remains preserved; G05a island construction is the separately
qualified next increment.

G05a island construction is now the bounded next checkpoint. See [island API/policy](../experimental/physics_gpu/ISLANDS.md) and `build/physics-g05-islands/verification.json`. Original G01–G04 response paths and numerical baselines are retained. G05a remains preserved; G05b adds only its separately qualified conservative
sleep/wake owner. Stop before warm starting or per-island solver scheduling.

G05b now adds the separately opt-in conservative [sleep/wake owner and idle gate](../experimental/physics_gpu/SLEEP.md). Its exact completed behavior, limitations, preserved original response baselines and cleanup are recorded in `build/physics-g05-sleep/verification.json`. Stop at G05b before broader sleep or per-island scheduling.


Oriented box/box detection is a separate bounded contact-geometry checkpoint.
See [geometry API and limits](../experimental/physics_gpu/BOX_BOX.md) and
`build/physics-box-box/verification.json`. The new patch stream preserves all
original sphere/OBB, history, response, island and sleep implementations/gates.
The nine-point upper bound is checked, with explicit nearly parallel construction
limits and nonnegative depth. The ordinary SDK and Yo Frankie campaign do not
adopt these patches. Stop here before multipoint history/response or box stacking.


The separate bounded [box response checkpoint](../experimental/physics_gpu/BOX_RESPONSE.md)
adds multi-point normal/Coulomb solving only for its explicit experimental box
owner. The original 30-Hz/64-sweep three-cube failure remains a convergence
counterexample, verified against an independently solved small system and residual
histories. The distinct96 policy permits up to 50% extra patch passes and needs66
in the unchanged scene. Supported centered rest fixtures and timestep/domain limits,
physical energy/work/drift/penetration checks, preserved gates and cleanup are in
`build/physics-box-response/verification.json`. No general stack, warm-start,
parallel, new-geometry, sleep or ordinary campaign feature is promised.
