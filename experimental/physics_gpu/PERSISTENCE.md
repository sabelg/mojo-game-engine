# G03c GPU one-point contact history

G03c adds persistent pair/feature lifetimes for the qualified sphere/sphere and
sphere/oriented-box pairs. It keeps one current point per supported pair, with
GPU-owned history, matching and event publication. It is not a general convex
multi-point manifold, response solver or accumulated-impulse cache. Geometry
and input ranges remain G03a/b's; no new shape or broad-phase algorithm is added.

## Representation and matching

`GpuContactHistory` owns a `GpuCollisionWorld` and shares its compute context.
Call body/shape commands through `history.world`, then `history.update()` to
observe contact history. The owned world/context must not be replaced. Raw
`world.detect()` does not advance history. The API remains single caller and
synchronous, with explicit completion before host observation.

Each GPU record contains the complete 11-word canonical pair identity: shape
slots/generations/revisions, attached body slots/generations and world namespace.
It adds a UInt64 lifetime ID, UInt64 age, feature tag, ambiguity flag and status,
plus ten Float64 values for current normal, separation and world witnesses.
Records are dense in canonical slot order. A fixed 2,016-entry pair-index map
locates the previous record; there is no host matching/allocation registry.

Reuse requires exact complete identity and feature equality, both observations
nonambiguous, and old/current normal dot product at least `0.95`. This is a newly
declared retention policy, not a relaxation of geometry tolerances. Reused IDs
keep their identity and advance age. A new lifetime gets the next monotonically
allocated ID and age one. IDs are scoped to the owning history/world namespace;
they never wrap or recycle. Age and epoch exhaustion also reject publication.
Age counts successful history observations, not time or body-integration steps.

Features distinguish ordinary versus coincident sphere pairs; box exterior
face/edge/corner regions; and selected interior escape faces. Exterior box tags
encode each local axis as negative/outside, inside, or positive/outside. Interior
selection retains G03b's exact local X/Y/Z and positive-zero tie convention.
Coincident spheres and equal nearest escape faces, including positive/negative
ties at zero on the selected axis, are ambiguous. They conservatively start a
fresh lifetime each update, ending the previous one. No normal/feature smoothing
or epsilon buckets are introduced.

`ContactFrame.active` contains all current contacts with `NEW=1` or
`PERSISTENT=2`. `ended` contains old unmatched records with `ENDED=3`, including
their last committed geometry and identity. Active records are sorted by current
canonical pair order; ended records are sorted by previous canonical pair order.
Revisions, shape/body removal and generation reuse cannot match an old object.
Separation ends a lifetime; recontact creates a new ID. Feature or sharp-normal
changes end/restart the lifetime even if the pair itself remains in contact.
The point is recomputed each observation; this tracks pair/region continuity,
not a permanently anchored surface point. Returned frames are value snapshots.

## Transaction and lifecycle boundary

GPU feature classification and matching stage a candidate cache. History/event
capacity and ID/age/epoch checks precede current-cache/state commit. On failure,
no new frame is returned and cache count, records, epoch and next ID retain their
last committed values. A retry compares with that last successful observation;
failed or unobserved intermediate geometry does not itself emit an event.
The underlying geometry phase must also succeed before matching can run.

Body/shape commands are separately committed operations. Their effects, including
G03a/b's successful orphan reconciliation before detection, are not rolled back
by a later history failure. The history transaction governs publication of its
cache/events, not the complete physics step. Old cached keys remain historical
until the next successful update; they cannot match a reused object. `last_error`
reports geometry or history phase rejection. Geometry's original codes are
retained; new codes are history capacity 43, event capacity 44, exhausted IDs 45,
age 46 and epoch 47. Diagnostic/cache staging buffers are not published frames.

`close()` synchronizes the owned world and rejects later updates. Buffers free
with owner destruction; retaining a closed owner retains its allocations. No
asynchronous consumer or in-flight solver-cache reuse contract is introduced.

## Capacity, memory and transfers

Geometry limits remain 64 shapes, 256 bodies and 2,016 possible unordered pairs.
History capacity defaults to 256 and may range `[0,2016]`. Event capacity defaults
to 512 and may range `[0,4032]`; an update can emit current active records plus
all old ended records. Neither contacts nor events are silently truncated.

Current/scratch/diagnostic caches, event output, GPU feature/index/matched arrays,
state and summary buffers are allocated once. A cache/event record has 16 UInt64
words plus ten Float64 values, or 208 logical bytes. G03c explicit buffers total
307,844 bytes at default history/event capacities, or 2,145,284 bytes at their
maximum. Including maximum G02/G03a/b buffers, the upper bound is 3,121,948 bytes,
below the existing 16 MiB cap. Host frames/lists/mappings, runtime/compiler and
render memory are additional. Actual DMA bytes/directions are unmeasured; the
existing staged Vulkan path is retained, without zero-copy/direct interop claims.

## What future warm starting can use

Complete identity, revisions, feature/ambiguity, normal and age supply
correspondence/invalidation information. Current and ended world-space witnesses
and separation supply geometry diagnostics. No impulse, tangent frame, stable
local anchor, effective mass, timestep correlation or friction state is cached.
`PERSISTENT` is not permission to reuse an impulse. G04 must qualify the solver,
local-anchor/displacement rules, mass/dt changes, normal/tangent transport,
restitution/friction and energy/momentum behavior before warm starting is enabled.

## Independent qualification and review

`contact_reference.mojo` consumes independent CPU matrix/corner/six-face geometry.
It classifies ambiguity by enumerating six escape faces and matches prior records
with a linear identity search, independently of the GPU feature/index-map and
transaction kernels. Geometry retains exact membership/identity/order and
`abs(error) <= 1e-9 + 1e-12 * abs(reference)`, squared-normal error `1e-12`, and
the signed witness relation. No G01/G02/G03a/b gate is relaxed.

`test_g03c.mojo` source and precompiled-API suites verify explicit lifetime/age
sequences, four-step live integration, separation/empty/recontact, exterior
face/edge/corner/interior transitions, same-geometry reshape revisions, ambiguous
coincident/inside contacts, and gradual versus sharp normal changes. Shape/body
removal and reuse, foreign/stale/invalid command rejection, full-cache rollback,
geometry failure and capacity/counter exhaustion are covered. The dense fixture
emits 2,016 active contacts and 4,032 new/ended events with exact deterministic ID
sequences and guards. Test-only GPU counter setup makes exhaustion finite; no
production reset API is added. Original G01/G02 and G03a/b source/precompiled
regressions passed unchanged.

```sh
python3 scripts/qualify-contact-history.py test --slot-confirmed
python3 scripts/qualify-contact-history.py packaged --slot-confirmed
python3 scripts/qualify-contact-history.py demo --slot-confirmed
```

The launcher uses the unchanged matching Mojo/MAX environment. Native builds use
one compiler thread with a 180-second deadline; precompile is finite serialization
with no CLI thread option. Runs use a 30-second deadline, 32 GiB available-memory
reserve and temperature observation only. H3 remains paused in the exclusive slot;
normal settings, drivers, hardware controls and retired cutoff behavior stay put.

The opt-in `games/yo-frankie/examples/gpu_contact_history_review.mojo` runs three
boxes and five GPU spheres for 60 frames. It observes revision/reuse, separation
and recontact, then displays simultaneous new/persistent/ended events. Green
marks new active contacts, orange persistent contacts, and purple the last
geometry of ended contacts. Active glyphs are lifted 0.75 m; ended glyphs 1.4 m,
explicitly labelled. All 60 GPU event frames are checked against the independent
reference after rendering, and Vulkan validation must report zero errors.
Campaign, assets, saves and earlier scenes remain unchanged. No response or
impulse reuse is performed.

Receipts: `build/physics-g03c/{test,packaged,demo}-qualification.json`. Commands,
hashes, rollback, preview and preservation/cleanup evidence:
`/home/user/Documents/Codex/2026-10-12/task/physics-g03c-20261012/verification.json`.
Remaining G03 work includes planes, box/box, general multi-point manifolds and a
scalable broad phase. Stop at this qualified history increment before G04 response.
