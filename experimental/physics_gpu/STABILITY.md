# G04 solver stability checkpoint — projection before velocity

The opt-in `GpuStableFrictionResponse` corrects the ordering/anchor bias found in
[G04b](FRICTION.md). Original G04a/b implementations, tests, original 60-Hz failure
and 240-Hz passing review are retained. This is a bounded solver correction,
without new shapes, coefficients, warm starting or parallel solver scheduling.

```mojo
from experimental.physics_gpu.stable_friction import GpuStableFrictionResponse

var response=GpuStableFrictionResponse()
# Existing lifecycle/shape API: response.response.normal.history.world
_=response.response.normal.history.world.bodies.step(1.0/60)
var report=response.resolve(1.0/60,coefficient=.8)
# report.friction contains G04b's report; initial/projected contact counts
# identify contacts released by projection.
response.close()
```

The recommended experimental selection now exports this owner as
`experimental.physics_gpu.recommended.GpuPhysicsResponse`, with a separate
`qualify-gpu-physics.py` source/packaged/live review using one 60-Hz physics step.
Original owner defaults and counterexamples remain named regression paths. The
ordinary engine SDK/campaign does not adopt this GPU API; that remains separate work.

## Diagnosis: point velocity and the effective rolling radius

Material contact velocity is `v_COM + omega × (p_surface − COM)`. G04b evaluates
both body velocities at the overlap-witness midpoint, then translates COMs without
re-solving velocity. On a gravity-supported sphere/fixed floor, the pre-solve
midpoint lever is `ell_old = r − (s + 0.5*g*dt²)/2`, where s=1e-5 m is resting slop.
The normal impulse removes the downward free-step speed. Friction converges to
`vx + ell_old*omega_z = 0`, while actual surface velocity is
`vx + r*omega_z = omega_z*(s + 0.5*g*dt²)/2`.

The original high-friction 60-Hz scene measures −0.00341857563 m/s, matching this
prediction. It is deterministic wrong-radius rolling, not physical sliding,
an iteration failure or a hardware/thermal issue. The low-friction sphere has
insufficient friction impulse to stop surface slip; its roughly +3.71 m/s slip
is physically expected. An original first-frame torque transient is included
in analytic predictions: the scene starts at exact contact before resting slop
is established. Neither the original initial state nor contact epsilon changes.

## Corrected ordering and publication

1. Strictly detect and validate original contact identities/geometry against
   authoritative GPU bodies with unchanged G04a setup/profile guards.
2. Project a private body candidate using the unchanged split COM solver.
3. Redetect at the projected pose. Released contacts are allowed. A newly created
   contact rejects with code 65; excessive remaining penetration rejects with 60.
   Initial capacity and other original errors propagate. No constraint is kept
   merely to glue a genuinely separated rotating pair together.
4. Copy the validated projected pose to a second private SoA. Build fresh
   midpoint/Jacobians and incoming restitution targets there, then perform a cold
   normal/friction velocity solve. There is no later COM translation.
5. Validate final geometry/normal speed and publish all body fields once.

The intermediate host fence reads status/count/projection diagnostics only; body
state stays on GPU. If either phase fails, authoritative bodies, pending forces,
body registry and committed history remain unchanged. Commands, integration,
orphan pruning and explicit history publication remain separate commits. Driver
allocation failures/asynchronous callers are not qualified.

Velocity impulses at a common point conserve closed linear/angular momentum at
the projected COMs. Projection changes orbital angular momentum separately by
`sum(delta_COM × incoming_linear_momentum)`, which the coupled dynamic test
accounts explicitly. Projection changes potential energy while leaving kinetic
state unchanged; it is not a physical force/work integrator.

The original APIs retain their original zero-friction/G04a equivalence gates.
The new ordering uses the projected geometry even when mu=0; equivalence to the
old ordering is not promised. Restitution targets use incoming velocity at the
projected contact point. Closed-form bounce/energy tests cover e=0/0.5/1.

## Verified 60-Hz improvement and remaining error

For the same original radius-0.35, mass-1, vx=3, omega_z=4, mu=0.8 scene, the new
lever is `ell_new = r − s/2`. Midpoint slip converges to rounding error, while
surface slip is `omega_z*s/2`, independent of dt in this floor fixture.

| Physics rate | Original measured surface slip | Corrected measured surface slip |
|---|---:|---:|
| 30 Hz | Not rerun for this original scene | −0.0000248980 m/s |
| 60 Hz | −0.00341858 m/s | −0.0000248980 m/s |
| 120 Hz | Not rerun for this original scene | −0.0000248980 m/s |
| 240 Hz | −0.000236926 m/s | −0.0000248980 m/s |

The corrected 60-Hz path passes the **original 0.001 m/s gate**, with one physics
step per frame. Scene, coefficient, initial speed/spin, radius and gate remain
unchanged. The original 60-Hz failure remains an explicit expected counterexample.
Exact material-surface sticking is still not qualified: the midpoint and retained
slop leave an O(s*omega) error. No epsilon/tolerance was enlarged to obtain this result.

## Energy and timestep quality requirements

The floor ledger distinguishes kinetic loss from potential work of COM correction.
At steady support, normal free-step kinetic loss `0.5*m*g²*dt²` cancels the
potential increase from restoring the free-fall displacement. Sliding tangential
loss follows `j*v_t_in + 0.5*k*j²`; closed impulse/torque/energy laws and independent
CPU trajectories verify it. Five simulated seconds of corrected floor rolling at
60 Hz showed zero measured total-energy drift after the first second, within the
unchanged 1e-8 check. This does not establish general long-duration conservation.

On a fixed incline, physical no-slip rolling has nonzero COM acceleration. The
discrete cold e=0 projection of gravity-induced point slip also dissipates
`0.5*(g*sin(theta)*dt)²/k` per step, even in the sticking regime. This is numerical
constraint dissipation, distinct from physical sliding loss. At theta=0.1 rad,
radius 0.5, first-second measured losses were 0.00238135 J at 60 Hz and 0.00123948 J
at 120 Hz, including the initial slop potential offset. Both match the independent
work prediction. Removing that offset halves the loss under timestep refinement.
The subsequent low-coefficient sliding phase also matches the full step work ledger.

Position integration still applies friction impulses after free advancement. For
the unsaturated low-mu floor trajectory, displacement differs from continuous
sliding by `0.5*mu*g*T*dt`; the discrete analytic law is checked at all four rates.
Thus substeps remain a legitimate explicit integration/contact-quality choice.
This correction removes the avoidable dt² anchor-slip term, not every timestep
error, numerical dissipation or rotating collision-timing limit.

## Qualification and limits

The independent CPU path uses matrix/six-face geometry, scalar inertia tensors,
spectral tangent solve and KKT stopping, with projection explicitly before fresh
velocity constraints. Analytic checks are independent of those implementation
helpers. Source and precompiled tests cover:

- Original 60-Hz failure and original 240-Hz pass; corrected original scene at
  30/60/120/240 Hz; physical low-mu sliding and high-mu rolling laws.
- Five-second support, gravity/normal/friction energy bookkeeping, incline
  rolling-to-sliding transition and energy refinement at 60/120 Hz.
- Coupled/shared contacts, common-point momentum plus projection orbital change,
  alternate tangent bases, and fresh rotating dynamic-box geometry. The free
  rotating pair legitimately releases; GPU detection and independent narrow
  geometry agree during its separated motion.
- Near-zero speed, projected bounce/restitution laws, zero coefficient, full
  64-contact capacity, genuine contact release, and original signed touching/
  one-ULP boundary fixtures.
- Material, corrupt identity, topology, projection-iteration, capacity and
  unsafe restitution-energy failures, with exact body/force/cache rollback.

Original mass/size/dt/precision/iteration/capacity and all G01–G04 numerical gates
are unchanged. Newly created contacts during projection are rejected, rather
than silently reprojecting an expanded graph. Deep/interlocked scenes, exact
surface anchors, rotational position correction, static stacks and extreme
conditioning remain unqualified. The new owner remains synchronous, Float64,
serial and NVIDIA GB10-only, with no performance comparison claim.

One additional private SoA costs 47,472 bytes. Maximum corrected owner explicit
buffers total 1,760,952 bytes. The two-owner old/new trajectory comparison totals
3,474,432 bytes; driver/compiler/host allocations are additional. DMA is unmeasured.

```sh
python3 scripts/qualify-stable-friction.py test --slot-confirmed --build
python3 scripts/qualify-stable-friction.py packaged --slot-confirmed --build
```

Use the unchanged pinned environment and exclusive slot, one native compiler
thread, 180-second compile and 30-second run bounds, 32 GiB available-memory
reserve and temperature observation only. H3 stays paused and restored settings
stay unchanged. The stability investigation itself used numerical evidence. The subsequent
recommended integration adds a separately named 60-Hz live game review and four
actual rendered preview frames; the original game review remains preserved.

Receipts: `build/physics-g04-stability/{test,packaged}-qualification.json`.
Reproducible measurements, original/final logs, source hashes, regressions,
preservation and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-g04-stability-20261013/verification.json`.
Stop at this tested stability checkpoint; broader integration/anchor/ordinary-engine/default-campaign
changes require separate scope.
