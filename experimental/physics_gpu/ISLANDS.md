# G05a bounded GPU contact-island construction

`islands.GpuContactIslands` owns the existing G02 body registry and G03 collision
world, plus resident island output/scratch buffers. Its `world` exposes the same
body/shape commands. This separate experimental owner is not wired into
`recommended.GpuPhysicsResponse`; its implementation, solver ordering and prior
numerical gates remain unchanged. This checkpoint supplies topology metadata
only, not sleep, wake propagation, warm starting, scheduling or performance.

## Graph and fixed-body policy

Every active body with positive mass is a vertex, including bodies with no shape
or contact. A current touching/overlapping supported contact between two dynamic
bodies is an undirected edge. A dynamic/fixed contact belongs to that dynamic
body's component, but fixed bodies are anchors and do not connect components.
Static-only contacts have no dynamic island and remain observable in the output.

Fixed bodies have zero inverse mass/inertia and cannot transmit a response from
one dynamic body to another. Unioning through a shared floor would falsely couple
independent piles and obstruct later independent solves/sleep. Future moving
kinematic bodies, joints, filters and sensors need separately defined policies;
they are not covered by this profile.

A component label is its minimum current body slot together with that root's
exact UInt64 generation and world namespace. It is deterministic for the same
current identities/topology, not a persistent island lifetime ID. Root removal,
slot reuse, merges and splits can change it. Live fixed members and static-only
contacts have root slot -1 and generation 0; this sentinel is not a usable handle.
Contact records are sorted by canonical shape-slot pair, independent of union or
prepared-record order. All live members are sorted by body slot.

## Device work and publication

`build()` detects contacts using the resident registry, then revalidates prepared
records against freshly regenerated GPU bounds/contact flags. It launches a
single GPU thread for identity/completeness validation, min-root union-find,
canonical label/contact construction, capacity checking and commit. Parent links
strictly decrease and traversals are bounded by 256. Float64 body/shape validation
and existing sphere/sphere and sphere/OBB geometry retain their admitted ranges.

Before committing, the device checks all live bodies, registry tags/generations,
world ownership, canonical shape endpoints, shape generation/revision and body
identity. It rejects duplicate, omitted, stale or non-current contacts, invalid
counts, upstream detection failures, island overflow and epoch exhaustion.
Candidate metadata is private. On failure, published member/contact words and
epoch/count state are unchanged; unused contact tails are cleared on success.
The build never integrates, projects or modifies body state.

The transaction covers island publication. Earlier caller body/shape commands and
collision-world orphan reconciliation are not rolled back when a build fails.
`snapshot()` describes the last successfully published epoch; it may be historical
following caller edits or a failed build. Callers must obtain a successful build
for current topology. Previously returned frames are value observations.

Host work allocates buffers, enqueues existing commands/kernels, observes completion
and reads error/count metadata. `build()` reads two Int32 status words and a six-word
UInt64 publication state (four fields and two guards); existing detection reads its bounded summaries and
uses ordinary command staging. No host connected-components computation or live
body registry is used. `snapshot()`/`update()` explicitly download published
membership/contact diagnostics, including fixed-capacity tails in the current
implementation. Actual DMA bytes are not measured; no zero-copy claim is made.
GPU bodies/labels remain resident between calls. Scope close is idempotent.

## Capacity and representation

The existing limits are 256 bodies, 64 shapes (one per body) and 2,016 supported
contacts/pairs. `pair_limit`, `contact_limit` and `island_limit` select explicit
budgets in [0,2016], [0,2016] and [0,256]. Zero and full budgets are tested. At most
64 shaped bodies can share a contact component; unshaped dynamic bodies are
singleton islands. Box/box contacts and broader geometry remain excluded by G03.

Output uses six UInt64 words per body slot and thirteen per contact, with guard
words. Two output/candidate copies, parent/seen arrays, publication state and
status consume 453,128 bytes at full capacity, in addition to the existing
collision/body owner. Body slots remain stable; no dense compaction, ordered
member-range scan or independent solver work queues are produced yet.

This is a serial correctness baseline on NVIDIA GB10 using the matched pinned
Mojo/MAX profile. It is not a throughput/scale result. The G05 sleep/wake,
compaction, filters/events and solver scheduling portions remain unimplemented.

## Qualification and diagnostic

`test_islands.mojo` computes expected geometry with the existing independent
scalar CPU sphere/OBB oracle, then uses queue-based flood fill (not the device
union algorithm). Expected edges never come from GPU label/contact readback.
Exact integer/identity comparisons cover AABB-only false positives and excluded
box/box edges, isolated/unshaped bodies, disconnected
chains, cycles, shared static boxes, static-only contacts/chains, reversed
creation/contact order, byte-preserved bodies, fresh creation/removal/split/rejoin,
reused generations, stale pose/key/revision rejection, malformed/incomplete and
oversized records, corrupt body/registry input, publication/tail clearing and rollback, epoch
exhaustion, empty/zero budgets, 256 singleton islands and full body/shape/contact
capacity. Existing numerical response budgets are unchanged.

Run `python3 scripts/qualify-islands.py MODE --slot-confirmed` in the development
checkout; MODE is `test`, `packaged` or `demo`. The precompiled test isolates the
new API under a distinct package name. All native builds use one thread, 180s
compile and 30s run deadlines and the existing 32 GiB reserve. Temperatures are
observed, without retired diagnostic cutoffs or application-setting changes.
H3 stays paused. CPU geometry/flood fill appears only in qualification/diagnostics.

The five-step actual GPU diagnostic creates a shared fixed floor, splits and
rejoins a dynamic chain, removes its root, then reuses the slot with a new
body generation. Its island counts are 2,3,2,2,2 and its final root is slot 1,
generation 2. It enqueues explicit edits and prints device-produced labels; it
is not a new physics-response or rendering feature.

Evidence: `build/physics-g05-islands/{test,packaged,demo}-qualification.json`,
`build/physics-g05-islands/demo-run.log` and
`build/physics-g05-islands/verification.json`. Stop at this island-construction
checkpoint before sleep or solver scheduling. No community code or dependency
was copied or adopted; no unresolved algorithm question required an external
troubleshooting reference in this increment.
