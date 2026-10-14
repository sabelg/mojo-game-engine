# G03a sphere checkpoint and shared lifecycle contract

G03b now qualifies sphere/oriented-box detection in the same registry. See
[OBSTACLES.md](OBSTACLES.md) for current supported pairs, descriptor/wire layout
and memory accounting. This page retains the original sphere checkpoint and
its lifecycle qualification; its source/precompiled suites passed unchanged
against the current shared implementation.

This qualified experimental increment adds owned spheres, GPU AABB candidates
and sphere/sphere contact geometry to the persistent G02 body world. It detects
contacts without changing body state or applying impulses. G03b adds oriented
boxes; sphere/plane, meshes, a scalable broad phase, persistent manifolds, response,
restitution and friction remain future work.

## Qualified profile

The deployment profile remains NVIDIA GB10/Linux ARM64, Float64, Mojo
`1.2.0.dev2026092905` and isolated `max-core 26.7.0.dev2026092905`. No new dependency
or lockfile change is required. The ordinary Atlas compiled API/source SDK stays
independent of this experimental GPU package.

- At most 256 persistent bodies, 64 spheres and 64 ordered shape commands per
  transaction. Each body may own one sphere; compound shapes are unsupported.
- Radius is finite and in `[1e-6, 1e4]`; each finite body-local center component
  has absolute value at most `1e6`. The transformed world center has finite
  components with absolute value at most `1e9`.
- Candidate/contact output limits independently default to 256 and may be
  configured in `[0, 2016]`. Exhaustion raises an error and publishes no frame;
  truncated contact lists are never presented as successful detection.

`GpuCollisionWorld` owns a G02 `GpuWorld` and shares its context. Device buffers
hold shape liveness, UInt64 generation/revision, owner namespace, attached body
slot/generation, kind, radius and local center. The host stages commands and
observes results; it does not maintain a second allocation or liveness registry.

`SphereCommand.attach`, `detach` and `reshape` run as an ordered GPU transaction:
copy to scratch, prune attachments whose body identity is no longer live, apply
commands, and commit only if every command succeeds. Shape slots use lowest-free
allocation. Detach advances the generation; generation exhaustion retires the
slot. Reshape advances the revision and rejects revision exhaustion. Shape and
body handles include the world's practical UInt64 namespace from G02. Body
mass/inertia are not changed by shape descriptors; a radius change changes only
collision geometry.

Removing/reusing a body invalidates its old attachment. Detection first performs
an empty successful shape transaction to reconcile such orphans. This pruning
may commit even if subsequent detection fails its geometry/output limits; the
body world is never changed by detection. Old returned `DetectionFrame` values
are copies of an earlier observation, not live contacts or a persistent cache.
The frame epoch counts successful host observations rather than simulation steps.

## Geometry and ordering

The device computes each center as COM position plus quaternion-rotated local
center. A fixed 64-by-64 all-pairs kernel filters unique unordered pairs by
inclusive AABB overlap. This is a bounded completeness prototype, not a scalable
broad phase. Compaction emits canonical shape slots `a < b` in lexicographic
order; keys contain shape generations/revisions and attached body generations.

For a surviving candidate, separation is `distance - (radius_a + radius_b)`.
Separation zero counts as contact, with no added touching epsilon. The unit
normal points from A to B; coincident centers use deterministic `+X`. Witnesses
are `center_a + normal * radius_a` and `center_b - normal * radius_b`. AABB false
positives remain candidates without a contact. There is one contact per sphere
pair; no solver, warm start or manifold cache is implied.

Bounds/contact arithmetic, flags and output compaction execute on GPU. The
independent CPU oracle computes centers with an explicit quaternion rotation
matrix and scalar brute-force geometry; it reuses only result types, not GPU
bounds/contact helpers. Membership, keys and ordering must agree exactly. Scalar
geometry uses `abs(error) <= 1e-9 + 1e-12 * abs(reference)` and squared-normal
error at most `1e-12`. G01/G02 reference code and budgets remain unchanged.

## Memory, transfer and lifetime

The byte counts below describe the original G03a four-field layout. The current
G03b eleven-field layout/144-byte packets supersede them; see OBSTACLES.md.

All shape, scratch and output buffers are allocated once at construction and
remain device owned. A logical shape command is 88 bytes; fixed guarded command
input buffers total 5,664 bytes even for a smaller submitted packet. Mapping may
move entire buffers. Actual DMA bytes/directions are not measured.

G03 adds 208,016 fixed bytes plus output buffers: 65,584 bytes at default
256/256 limits, or 516,144 bytes at 2016/2016. Including G02's maximum-command
allocation of 231,688 bytes, explicit buffers total at most 955,848 bytes, below
the existing 16 MiB cap. Host lists/mappings, compiler and runtime/context memory
are additional. Output reads contain pair/contact keys and ten Float64 geometry
values per contact; the game separately uses G02's staged pose snapshot before
the existing Vulkan upload. No direct CUDA–Vulkan sharing or zero-copy is claimed.

The API is synchronous and single caller, with explicit device synchronization
before host observation. `close()` waits and rejects subsequent operations;
buffers are released by owner destruction, not immediately while a closed owner
is retained. No asynchronous consumer/cache lifetime contract is implemented.

## Qualification and review

Run only with the confirmed exclusive CPU/GPU slot, keeping H3 paused:

```sh
python3 scripts/qualify-physics-contacts.py test --slot-confirmed
python3 scripts/qualify-physics-contacts.py packaged --slot-confirmed
python3 scripts/qualify-physics-contacts.py demo --slot-confirmed
```

The launcher uses the existing isolated environment and installs nothing. Changed
source/artifact fingerprints trigger a rebuild; `--build` forces one. Native
builds use one compiler thread and a 180-second deadline; precompile serializes
non-elaborated code with a CLI that exposes no thread option. Numerical/render
runs have a 30-second deadline. The existing reserve remains 32 GiB available
memory, with temperature observation only and finite sequential launches.

On October 12, 2026, source and precompiled-API GB10 runs passed separation,
touching/near-touching, overlap, coincident/near-coincident centers, diagonal AABB
false positives, 3-4-5 tangency with unequal radii and radius boundaries. A rotated
36-sphere local-offset grid over four integration steps matched the independent
CPU oracle with complete, duplicate-free, ordered candidates. Tests also passed
shape revision, duplicate body attachment, invalid radius/kind/slot rejection,
mixed-command rollback, body removal/orphan pruning/reuse and stale shape
rejection, dense 64-sphere/2,016-pair capacity, explicit pair/contact overflow,
world-center range failure, closed-world rejection and unchanged body storage.
G01 numerical and G02 lifecycle/residency regressions passed unchanged.

The subsequent G03 guard checkpoint closed the two previously source-only
coverage gaps through the same source and precompiled-API suites. All new guard
fixtures have executable GPU evidence; production lifecycle/geometry code and
the CPU oracle are unchanged. A test-only one-thread device setup seeds an
active shape's counters near `UInt64.MAX`, making exhaustion finite without
adding a production mutation API. Expected counters, slot identities, retired
state and cleared descriptors are explicit CPU-side assertions, not calculated
by the device allocator. Contact identity/geometry still uses the independent
matrix/scalar oracle.

| Fixture in `test_g03.mojo` | Newly verified GPU behavior |
| --- | --- |
| `foreign_shape_namespaces()` | Two worlds with matching slot/generation and different namespaces: foreign detach/reshape and foreign body attach reject; zero owner rejects; a preceding valid reshape rolls back when a later foreign command fails. Both worlds' registry/body snapshots remain unchanged. |
| `shape_counter_exhaustion()` | Revision `MAX-1` advances to `MAX`; another reshape and mixed batch reject atomically. Shape generation `MAX-1` advances to reusable `MAX`, then final detach retires it permanently with generation still `MAX`. Old/zero/wrapped-looking handles reject. Detach/reuse and body remove/create never reclaim the retired slot; one retired slot means 63 live shapes exhaust capacity. |
| `exhausted_shape_orphan_retirement()` | Removing/reusing the attached body before reconciliation retires a `MAX` shape rather than attaching it to the new body generation. A failed foreign command rolls back even pending orphan retirement. Later detach/reuse and another body lifecycle transition cannot resurrect the retired shape or its old contact keys. |

The shared `shape_reject()` helper now requires no returned command result, no
epoch advance, exact unchanged published shape metadata/descriptors and exact
unchanged body state/registry on failure. New fixtures also compare subsequent
detections and previously returned frame copies with independent expectations.
The original `lifecycle_and_invalid()` already covered ordinary generation reuse
and stale shape rejection; it remains intact. G02's
`capacity_and_retirement()` tests body exhaustion only and remains unchanged.
No production bug was found; no limits or tolerances were relaxed.

Updated guard receipt, exact commands/artifact hashes, original rollback copies
and cleanup evidence:
`/home/user/Documents/Codex/2026-10-12/task/physics-g03-guards-20261012/verification.json`.
The earlier live game review was not rerun for this test/documentation-only
checkpoint; its production code, rendered image and original receipt are
preserved as the earlier G03a evidence.

`games/yo-frankie/examples/gpu_contacts_review.mojo` detects eight live GPU
spheres for 60 frames. It reshapes a sphere at frame 20, removes/reuses a body and
shape at frame 30, and compares the independent CPU geometry after rendering.
The final scene has four candidates and three contacts, with persistent body
addresses and zero Vulkan validation errors. Red spheres have detected contacts;
blue spheres do not. Magenta/cyan witnesses and yellow normals are lifted one
meter for visibility, explicitly labelled in the image. Spheres overlap because
response is absent; the preserved legacy game controller remains CPU based.

Receipts: `build/physics-g03/{test,packaged,demo}-qualification.json` and
`games/yo-frankie/build/frankie-gpu-contacts-rendered.json`. The image is
`games/yo-frankie/build/frankie-gpu-contacts-demo.bmp`. Exact commands, hashes,
rollback files, corrected initial failures and preservation/resource evidence
are in `/home/user/Documents/Codex/2026-10-12/task/physics-g03-20261012`.
No benchmarks, production performance, other hardware, complete G03 or G04
solver qualification is inferred. Stop at this verified G03a checkpoint.
