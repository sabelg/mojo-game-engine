# G03b GPU sphere versus oriented-box geometry

G03b adds finite oriented boxes for floors, ramps, walls and obstacles to the
GPU-owned G03 shape registry. It generates contact geometry without applying
response, restitution or friction. Fixed and moving box transforms are read
from committed G02 GPU body state; no CPU collision fallback or host allocation
registry is introduced.

## Supported pairs and profile

| Pair | Candidate/contact support |
| --- | --- |
| Sphere/sphere | Existing G03a geometry and gates retained. |
| Sphere/oriented box | Qualified in either canonical slot order, with one contact per pair. |
| Box/box | Excluded from candidates and contacts, even if their AABBs overlap. |
| Plane, mesh, convex hull or compound | Unimplemented. A finite thin box can represent a floor; this is not an infinite plane. |

Candidate completeness applies only to the supported pair set. This remains a
fixed 64-by-64 all-pairs AABB prototype, not a scalable broad phase or general
convex solver. All shapes share 64 slots, one shape per body, and 64 commands per
submission; bodies retain the 256-slot G02 limit. Pair/contact output limits
independently default to 256 and range from zero to 2,016. Overflow raises and
publishes no frame. Dense 32-box/32-sphere testing emits 1,520 supported pairs;
the unchanged 64-sphere G03a fixture still covers the 2,016-pair maximum.

Sphere radius limits remain `[1e-6, 1e4]`. Each finite box half extent lies in
`[1e-6, 1e4]`; zero or negative extents are rejected. Each finite body-local center
component has magnitude at most `1e6`; each transformed world-center component
has magnitude at most `1e9`. Box local quaternion components must be finite with
maximum absolute component in `[1e-12, 1e12]`. Valid local quaternions are
normalized with scaling; sign and admissible scale do not change geometry.
These are input/finite-work limits; numerical budgets are qualified by the named
fixtures, not a theorem about every combination of extreme coordinates/scales.

## Ownership, commands and transforms

Existing `SphereCommand` factories and `submit_shapes()` retain their signatures.
`BoxCommand.attach(body, half, center, orientation)`, `reshape(shape, ...)` and
`detach(shape)` are submitted with `submit_boxes()`. Each submission uses the
same GPU transaction: scratch copy, orphan reconciliation, ordered validation,
whole-batch commit. The two typed submission methods do not offer an atomic
mixed-type attach batch. Detach can remove an owned shape through either method.

Shape kind is immutable: reshape cannot change a sphere into a box or a box
into a sphere (`SHAPE_KIND=39`); use detach/attach for a new kind. Unknown or
invalid descriptors still return `BAD_SHAPE=35`. Both kinds share GPU namespace,
generation, revision, body association, lowest-free allocation and exhausted-slot
retirement semantics. Mass/inertia remain body properties; geometry edits do not
silently change them. Failed command batches retain all published metadata,
descriptors and body state. As in G03a, a successful empty reconciliation may
prune orphan shapes before a later detection overflow/geometry error.

The GPU transforms a box center with the body's orientation and COM position.
Its axes use normalized `body_orientation * local_orientation`. Box AABB
half-widths are the sums of absolute rotated-axis components times half extents.
Sphere centers retain G03a's body-local offset convention. The body state and
shape descriptors stay device owned; detection reads them directly each call.

## Contact convention and ambiguous cases

Keys remain canonical shape slots `a < b`, in lexicographic order, with shape
generations/revisions and body generations. Touching means computed separation
zero, with no added epsilon. Each contact has normal `n`, signed separation,
and surface witnesses A/B satisfying `witness_b - witness_a = n * separation`
within the existing numerical gates. Reversing which shape has the lower slot
negates the normal and swaps witnesses while preserving separation.

For a sphere outside a box, the GPU clamps its center in box-local coordinates
to obtain the closest box point. Separation is closest-point distance minus
sphere radius. In sphere-first order the normal points toward the box point;
the sphere witness is center plus normal times radius.

For a sphere center on or inside the box, the GPU chooses the nearest escape
face. Exact clearance ties choose local X, then Y, then Z. Zero on the selected
axis chooses its positive face. In sphere-first order the normal is opposite
the escape direction, separation is `-(face_clearance + radius)`, the box witness
is on the escape face, and the sphere witness lies opposite the escape direction.
This records the full translation needed to remove the sphere from the solid box,
and preserves the signed witness relation even for deep overlap. It is a geometry
convention; no correction/impulse is applied. Ties are exact in computed Float64
coordinates; nearby non-ties may select another face, without smoothing or an
epsilon bucket. Sphere/sphere coincident-center `+X` behavior is unchanged.

## Independent qualification

`box_oracle.mojo` composes scalar rotation matrices rather than a quaternion
product, enumerates eight box corners for AABBs rather than the GPU's absolute
axis sums, and finds the nearest point by enumerating six rectangular faces
rather than the GPU's all-axis clamp/inside-clearance branch. It reuses only
result types and the existing independent CPU sphere-center oracle.

`test_g03b.mojo` checks exact membership, identity, ordering and errors. Geometry
retains `abs(error) <= 1e-9 + 1e-12 * abs(reference)` and squared-normal error
at most `1e-12`, plus the signed witness relation. Analytic fixtures independently
declare face/edge/corner tangency, separation, AABB false positives, deep/inside
overlap, boundary/center/tie decisions and radius/extent boundaries. Reversed
slot order, independently transformed feature normals, composed body/local
rotations, quaternion sign/scale and common rigid-transform invariance provide
metamorphic checks. A four-step rotating dynamic-box/local-offset trajectory
compares GPU integration and contact geometry with unchanged CPU R02a and the
matrix/six-face oracle.

Lifecycle tests cover box reshape revisions, foreign/stale handles, body-orphan
and explicit detach/attach reuse, kind immutability, full-descriptor clearing,
raw NaN/infinity/degenerate/out-of-range input and mixed-command rollback.
Capacity tests cover 64 mixed shapes, 65th-shape rejection, supported-pair
overflow, contact overflow, box/box exclusion and transformed center failure.
Unchanged G03a source/precompiled suites include its foreign namespace and
generation/revision exhaustion fixtures; G01/G02 regressions retain their gates.

## Memory and execution

The shared descriptor layout expands from four to eleven Float64 fields, adding
half extents and local quaternion; metadata remains seven UInt64 fields. Current,
scratch and diagnostic arrays are preallocated. Bounds now have 22 Float64
fields per shape. A logical shape command is 144 bytes (56-byte header plus
88-byte descriptor); fixed guarded command input buffers total 9,248 bytes.
The original G03a wire/memory accounting is historical and superseded here.

Fixed G03 buffers total 228,832 bytes. Outputs add 65,584 bytes at default
256/256 limits or 516,144 bytes at 2,016/2,016. Including G02's maximum-command
allocation, explicit buffers total at most 976,664 bytes, below the existing
16 MiB cap. Compiler/runtime context, host lists/mappings and render buffers are
additional. Actual DMA bytes/directions are unmeasured. The synchronous,
single-caller API, close/destruction behavior and staged Vulkan path remain;
no direct interop or zero-copy is claimed.

Use the existing matching Mojo/MAX environment; no install is performed:

```sh
python3 scripts/qualify-physics-obstacles.py test --slot-confirmed
python3 scripts/qualify-physics-obstacles.py packaged --slot-confirmed
python3 scripts/qualify-physics-obstacles.py demo --slot-confirmed
```

Compilation uses one native compiler thread and a 180-second deadline; precompile
serializes non-elaborated code with no thread option exposed by the CLI. Runs
have a 30-second deadline and keep the 32 GiB available-memory reserve. H3 remains
paused under the exclusive slot. Temperatures are observed; application settings,
drivers, hardware controls and retired cutoff behavior are unchanged.

The opt-in `games/yo-frankie/examples/gpu_obstacles_review.mojo` uses three boxes
and five live GPU spheres over 60 frames: finite floor, composed-rotation ramp,
inside/edge obstacle contacts, box revision at frame 20, body/shape reuse at 30
and rejection of the old box at 31. It compares the independent CPU oracle after
rendering and requires zero Vulkan validation errors. Witness/normal glyphs are
lifted 0.75 m for visibility and labelled; the obstacle's wire representation
shows inside contacts. The legacy controller remains CPU based and campaign,
assets, saves and earlier review examples are preserved.

Receipts: `build/physics-g03b/{test,packaged,demo}-qualification.json`. Detailed
qualification, rollback, initial corrected compiler failures and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-g03b-20261012/verification.json`.
Stop at verified detection geometry. Planes, box/box, persistent manifolds,
scalable broad phase and G04 response still require separate qualified increments.
