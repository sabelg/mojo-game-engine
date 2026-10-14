# Qualified bounded box/box detection and contact geometry

This increment adds a separate detection-only owner over the existing G02/G03
body/shape registry. It does not change the old sphere/sphere or sphere/OBB
geometry, one-point history, response, island or sleep owners. Box/box contact
patches use a distinct API/record type and never enter the old prepared response
buffers. Box stacking, manifold persistence/impulse reuse and multi-point solving
remain unqualified.

The implemented algorithm is 15-axis convex box SAT: six
face normals and nine edge-cross directions, normalized with max-component scaling.
Exactly zero cross directions are skipped; no arbitrary near-parallel angle cutoff
removes a representable separating direction. Current Float64 signed gaps determine
touch/separation without adding a contact epsilon. Face axes win equivalent axis
choices within a declared Float64 evaluation-resolution band; this selects a patch
feature and does not turn a positive separating gap into contact.

A face winner clips the incident face against the four extruded reference-face
side planes and the contact half-space. It emits a bounded patch of at most nine
points (eight for side clipping, with one additional contact-half-space cut), including reduced line/point patches at tangencies. An edge winner emits
one paired closest-edge point. No empty detected patch or output exhaustion may
silently drop or truncate a contact. Non-finite or unresolved geometry rejects
publication explicitly. Deep/contained overlap uses an oriented minimum-translation
support-face convention; ambiguous axis/direction ties are tagged.

Keys are canonical shape slots a<b with full generation/revision/body/namespace
identity. Point order is deterministic lexicographic pair-relative midpoint order.
The origin is A's committed center; witnesses are stored relative to it so large
world translations do not erase their local signed-distance relation. World-space
conversion is optional and subject to Float64 input/addition resolution. Exactly
zero direction projections use a deterministic sign convention; coincident/tied
pairs do not promise a unique normal under body permutation.

Clipping explicitly reuses on-plane endpoints. Adjacent or repeated vertices
indistinguishable within the declared scale-aware Float64 construction resolution
are coalesced and tagged; close but resolvable distinct vertices remain. Missing
expected patch vertices and near-duplicate emitted points are separate checks.
There is no claim of bitwise geometry invariance for unrepresentable translations,
perturbations or every extreme scale combination.

The independent reference constructs corners and projects their support extrema,
then enumerates face-polygon vertices/edge intersections and a monotonic-chain
hull. It does not reuse the device radius formula or Sutherland-Hodgman loop.
Edge witnesses use a scalar Gram-system solve, independently of the device's
transverse-projection calculation. Input GPU basis/centers are checked against
independent CPU transform matrices (axes at 32 binary64 eps); the reference then
uses these input bounds, never output contact normals or points. The returned
feature code identifies which face/edge convention to compare; independent SAT
separately verifies hit/miss and minimum support gap.

Read-only troubleshooting reference:
https://github.com/noeira/noeira/blob/7275baf96314b61db2bcbfd45652509a6ba5be7b/tests/physics3d/test_box_box_degenerate_stack.mojo
Only the ideas of separately measuring missing/duplicate points and perturbing
near-parallel/quaternion-rounding routes are used. No upstream code, numeric
fixtures, project install, solver or runtime dependency is copied/adopted.

One-thread finite 180s compile/30s run qualification, matched pinned Mojo/MAX,
exclusive slot and 32 GiB reserve remain unchanged. H3 stays paused; settings and
original numerical baselines are preserved. Stop at contact geometry before any
response/manifold-history/sleep adoption or performance work.


## API and publication scope

```mojo
from experimental.physics_gpu.box_box import GpuBoxBoxDetection
var detector=GpuBoxBoxDetection()
# Populate detector.world.bodies and detector.world.submit_boxes as in G03.
var frame=detector.detect()
```

`BoxBoxFrame` contains a UInt64 epoch, a list of `BoxContactPatch` values and the
unchanged legacy `DetectionFrame`. A patch has a full `PairKey`, origin, unit
A-to-B normal, signed SAT separation, feature code (A faces 0–2, B faces 3–5,
edge pairs 6–14), ambiguity/coalescing flags and points. Each point has two
origin-relative witnesses and signed separation. Separation is nonpositive;
`depth()` is `max(0,-separation)` and therefore nonnegative. Roundoff-sized
positive contact-plane reconstruction distances are coalesced to exact touch
and tagged, after strict SAT acceptance; no positive SAT gap becomes contact.

The owner is synchronous, single-caller, and detection only. All unordered live
box shape pairs are geometry candidates, including static/static and multiple
shapes on one body; collision filters and response eligibility are future work.
Private pair work runs on GPU, followed by serial bounded publication. Neither
integration nor response runs and body bytes remain unchanged. New patches are
never inserted into the old history, response, island or sleep contact buffers.

Admitted capacities: 256 body slots, 64 shapes, 2,016 box pairs, 1–9 points per
patch and at most 18,144 total points. Defaults are 256 patches/1,024 points.
An overlapping convex quad clipped by one halfspace gains at most one vertex;
five planes give the `4+5=9` upper bound. Each intermediate unique polygon count
is checked against `5+plane`, and scratch capacity is 16. Exhaustion, unresolved
geometry and invalid candidates fail explicitly instead of truncating output.
Error codes 100/101/102/103 are geometry/pair capacity/point capacity/epoch full.
Inherited G02/G03 errors remain explicit. `debug_publication()` is a diagnostic
raw-bit snapshot including output tails, guards and state, not a simulation input.

Atomicity covers the new box headers, patch/point data and UInt64 state. Legacy
detection and its orphan-attachment reconciliation occur first as separate
commits; a later box capacity failure can advance that legacy epoch/reconciliation.
Body/shape mutations also commit through their existing APIs separately. A box
failure leaves the previous complete box publication and epoch unchanged; a
successful detect rebuilds all candidates from current state, clears output tails
and publishes current generations/revisions. Old returned frames remain immutable
observations, not reusable solver constraints. UInt64 exhaustion rejects before
writes. `close()` is idempotent; closed detection/snapshots reject.

## Numeric limits and qualification

The inherited profile admits finite half extents [1e-6,1e4], local offsets up to
1e6, quaternion max-component scales [1e-12,1e12], and world centers up to 1e9.
Arithmetic is binary64. Strict computed support gaps classify separation; no
uniform exact-real predicate guarantee exists below evaluation/input resolution.
World-coordinate input rounding still applies, even though relative witnesses
avoid further large-world reconstruction loss.

Incident vertices, final projected witness midpoints and redundant collinear
construction vertices use
`32*eps*max(1,largest half extent)` resolution. Points farther apart than that
resolution stay distinct; pruning below it is tagged. Tests keep the fixed
`512*eps*max(1,extent)` witness shape/plane gate and verify signed-distance
relations, unique points and lexicographic ordering. Well-conditioned corners
are compared directly; intersection-position comparisons divide their forward
error envelope by the smallest nonzero edge/face-direction sine. This is an
explicit tested conditioning envelope, not a universal precision theorem.
Near-parallel lines/planes amplify small basis/dot-product rounding: the first
1e-12 seeded perturbation differed by about 0.000496 along an almost flat edge
while preserving plane membership. The original failed comparison is retained.
No uniform tight corner-position, invariant point count under unresolvable
perturbations, persistent feature/anchor, or bitwise body-permutation guarantee
is claimed. The implementation uses ordinary binary64 arithmetic, not adaptive
exact predicates or extended-precision clipping.

Source and isolated precompiled actual GB10 suites cover analytic face/edge,
separate/touch/deep/containment, line/point tangencies, rotated eight-point patches,
48 near-coplanar/quaternion perturbations, 96 general seeded rotated pairs and
scale/translation/creation permutation checks. A deliberately selected reference
face exercises all nine clipper points on GPU against the constructive reference;
it is a clipper-helper bound test, not a claim that SAT selects that face.
Lifecycle/revisions/stale/foreign/slot reuse, invalid packet transaction rollback,
range boundaries, mixed legacy geometry, all 256 bodies/64 boxes/2,016 patches,
8,064 dense-fixture points, guard/tail checks, zero/overflow capacities, retry,
epoch exhaustion and malformed candidate publication rollback are checked.
The six-edit device diagnostic emits 8→8→0→4→0→4 points across overlap, touch,
separation, reshape, removal and reuse without integration or response.

Reproduce with `python3 scripts/qualify-box-box.py MODE --slot-confirmed` for
`test`, `packaged` or `demo`. Final fingerprints, retained regressions, numerical
baseline comparisons and cleanup are recorded in
`build/physics-box-box/verification.json`. The historical partial checkpoint and
failed logs remain preserved separately. No box stack or box response is ready
through this increment; multipoint history/response adoption needs its own design
and qualification checkpoint.
