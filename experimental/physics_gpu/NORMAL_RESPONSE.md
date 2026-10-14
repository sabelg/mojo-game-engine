# G04a — bounded GPU normal response

This experimental Float64 correctness checkpoint resolves sphere/sphere and
sphere/oriented-box contacts on NVIDIA GB10. GPU body storage remains authoritative.
It adds normal restitution and shallow penetration recovery to G03b geometry;
G03c history remains correspondence metadata. Every solve starts with zero
impulses. The implementation runs canonical contact sweeps in **one GPU thread**:
it establishes numerical behavior, not parallel solver throughput or production scale.

```mojo
from experimental.physics_gpu.normal_response import GpuNormalResponse

var response = GpuNormalResponse()  # at most 64 response contacts
# Create bodies/shapes through response.history.world as in G02/G03b.
_=response.history.world.bodies.step(1.0/60)
var report=response.resolve(1.0/60,restitution=.6)
# Optional, separate correspondence publication:
var contacts=response.history.update()
response.close()
```

## Velocity law

For canonical A→B unit normal n, the common impulse application point is the
midpoint of the two geometry witnesses. With rA/B measured from each COM:

```
vn = n · (vB + ωB×rB − vA − ωA×rA)
k = invMA + invMB + (rA×n)·IinvA(rA×n) + (rB×n)·IinvB(rB×n)
target = −e * initial_vn  when initial_vn < −0.2 m/s; otherwise 0
λnext = max(0, λ + (target − vn)/k)
```

Apply −nΔλ to A and +nΔλ to B, including world-rotated principal inverse inertia.
Fixed bodies have zero inverse mass/inertia; fixed/fixed pairs are reported and
skipped. The projected accumulator is nonnegative; reducing a previous iterate
can have negative Δλ, but no attractive net impulse is retained. Common-point
application conserves closed-system angular momentum in velocity-only fixtures.

Each call uses 1–64 velocity sweeps (default 32). Complementarity residual must
be at most `1e-9 * max(1, 1 + max(abs(initial_vn)))`. Participating kinetic energy
must not increase by more than `1e-9*(1+energy_before)`. Coupled Newton restitution
can violate this energy bound even with e≤1; such a frame is rejected, not silently
made inelastic. The independent CPU reference demonstrates this rejection.

## Penetration and publication

Separate mass-weighted COM translation sweeps project linearized separation
toward `−1e-5 m` with a `1e-9 m` residual allowance. Position impulses are cold
and independent of velocity impulses. Orientation and velocities do not change
during projection. Initial dynamic penetration and maximum intermediate COM shift
must each be ≤0.25 m; 1–64 sweeps are allowed (default 32).

The solver redetects every supported pair against candidate body positions on
GPU. Excess penetration, newly approaching contacts, or output overflow reject
the transaction. All body fields are copied to authoritative storage only after
the complete candidate passes. Force/torque values and fixed bodies are preserved.
Integration, body/shape commands, orphan pruning and history publication are
separate transactions; failed response does not roll those earlier operations back.
COM projection makes no potential-energy or orbital-angular-momentum conservation
claim. Deep/interlocked scenes and rotational position correction are outside scope.

Prepared-contact qualification checks all 11 identity words, exact regenerated
shape bounds and raw contact geometry, plus finite/unit-normal checks. The public
`resolve` always freshly detects. Internal `_solve_prepared` exists for rejection
fixtures, not as a public stale-contact API. Failed impulse diagnostics are scratch
data and must not be interpreted as a committed response.

## Admitted profile and errors

The profile rejects inputs or iterates outside these limits; it is not a promise
that every combination converges:

| Quantity | Range |
|---|---|
| dt | 1/240–1/30 s |
| restitution | 0–1 |
| active dynamic mass / principal inertia | 0.1–100 kg / 1e-4–1000 kg·m² |
| COM / linear / angular component magnitudes | ≤1000 m / ≤20 m/s / ≤10 rad/s |
| quaternion norm squared error | ≤1e-10 |
| sphere radius / box half extent | 0.05–10 m |
| shape local-center component magnitude | ≤10 m |
| accumulated normal impulse | ≤1e4 N·s |
| bodies / owned shapes / response contacts | 256 / 64 / 64 |

Error codes: 50 contact capacity; 51 configuration; 52 profile; 53 identity or
freshness; 54 geometry; 55 velocity convergence; 56 energy; 57 initial depth;
58 position convergence; 59 shift; 60 post-detection; 61 numerical validity.
Earlier lifecycle/detection codes propagate. Rejection fixtures compare all body,
pending force, registry and committed history bytes before/after.

## Boundary correction and qualification

The original rotated tangency is retained: body +Y quarter-turn with local inverse,
sphere center (1.5,0.5,0), radius 0.5, box half extents (1,1,1). The old independent
CPU matrix normalized components through sqrt, then squared them; the resulting
matrix lost orthogonality. The CPU oracle now forms a scaled rational quaternion
matrix. It remains independent of GPU quaternion composition/rotation; GPU geometry
is unchanged. The correction preserves exact quarter-turn/inverse cancellation.

Touching retains **computed Float64 separation ≤0**, with no epsilon. Both current
paths compute exact +0 for the original case. Tests also cover ±one ULP in sphere
x, ±1e-12 and ±1e-8 m, both approaching and separating, rotated and unrotated.
Exact input, stored quaternion, old/new CPU separation, GPU separation and impulse
bits are recorded in `build/physics-g04a/{test,packaged}-boundary.jsonl`. The archived
old diagnostic currently yields −6.661338147750939e-16 at rotated tangency; an earlier
old build missed that contact, and its failure is retained. No exact old positive
gap was captured in that earlier log, and cross-build rounding invariance is not
claimed. Separate overlap fixtures continue testing transformed angular response.

Analytic and independent matrix-reference checks cover unequal masses, e=0/0.5/1,
fixed reflection, off-center angular response, rotated inertia, slot reversal,
rigid transforms, shared-body chains, shallow recovery, oblique tangential
preservation, and one-second support at 30/60/120/240 Hz. Failure tests include stale
pose/revisions, corrupted geometry, nonfinite/configuration/profile/capacity limits,
nonconvergence, deep overlap, shift budget, newly created contacts and energy gain.
Existing geometric, velocity, quaternion and earlier-stage gates are unchanged.

The game-owned `gpu_normal_response_review.mojo` runs 60 live GPU gravity/response
frames for five spheres and a fixed floor, with restitution 0.6, floor rebounds,
head-on velocity reversal and trails sampled from GPU poses. CPU replay happens
after rendering: all 60 energy/contact reports and five body-state checkpoints
are compared. Vulkan validation must report zero errors. CUDA–Vulkan data is staged;
there is no direct sharing or measured DMA/throughput claim.

Explicit buffers: response adds 427,892 bytes at 64 contacts; maximum G02/G03b
world plus default G03c history plus response totals 1,712,400 bytes (<16 MiB).
Driver/context/compiler/render allocations are additional. No host body registry,
CPU product solver, per-step body upload, friction, warm start, joints, CCD,
planes/meshes/box-box response or general multi-point manifolds are added.

## Reproduce

Use the unchanged isolated official Mojo/MAX environment in the [GPU README](README.md).
H3 remains paused and an exclusive slot is required. Each stage samples temperature
for observation, reserves 32 GiB available memory, bounds compile to 180 seconds
and numerical/render execution to 30 seconds. Native compile uses one thread.
No thermal cutoffs or hardware/settings changes are involved.

```sh
python3 scripts/qualify-normal-response.py test --slot-confirmed --build
python3 scripts/qualify-normal-response.py packaged --slot-confirmed --build
python3 scripts/qualify-normal-response.py demo --slot-confirmed --build
```

Receipts: `build/physics-g04a/{test,packaged,demo}-qualification.json` and
`games/yo-frankie/build/frankie-gpu-normal-response-rendered.json`.
Evidence, original failures, oracle rollback, exact boundaries, regressions,
preservation and cleanup: `/home/user/Documents/Codex/2026-10-12/task/physics-g04a-20261013/verification.json`.
The ordinary engine SDK/API stays unchanged. Stop at this checkpoint; parallel
scheduling, friction, impulse reuse and broader geometry need separately scoped work.
