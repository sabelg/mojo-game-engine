# G04b — bounded cold Coulomb friction

G04b adds a separate experimental `GpuFrictionResponse` owner over unchanged
[G04a normal response](NORMAL_RESPONSE.md). Body/shape ownership, geometry,
contact identity, energy/profile guards, split COM projection and body publication
remain unchanged. Simulation is authoritative on NVIDIA GB10 in Float64. Contact
sweeps run in one GPU thread; no parallel throughput or production-scale claim is made.

```mojo
from experimental.physics_gpu.friction_response import GpuFrictionResponse

var response=GpuFrictionResponse()  # 64 contact allocation limit
# Existing G02/G03 APIs: response.normal.history.world
_=response.normal.history.world.bodies.step(1.0/240)
var report=response.resolve(1.0/240,coefficient=.6)
# report.normal is the original ResponseReport.
# Optional, separate history publication: response.normal.history.update()
response.close()
```

## Material and contact law

One uniform dimensionless coefficient `mu` applies to all contacts in a resolve.
It is finite and in [0,2]. Static and kinetic coefficients are identical; there
is no material mixing, per-shape material registry, adhesion or rolling/spin
resistance. Changes of coefficient apply to a fresh cold solve. History never
authorizes impulse reuse. `mu=0` calls the original G04a velocity kernel and has
exact body-byte/report equivalence in the qualification fixtures.

G04a supplies a nonnegative normal impulse `lambda_n`, the restitution target,
and common witness midpoint p. Each contact has an orthonormal tangent pair t/u
and a symmetric positive-definite 2×2 tangential effective-mass matrix K,
including both bodies' translational and rotated principal-inertia contributions.
After the scalar normal update, remove the old tangent impulse's contribution
from relative point velocity to form v_free. Solve the whole circular disk:

```
minimize  0.5 * j^T K j + v_free^T j
subject to ||j|| <= mu * lambda_n
```

The unconstrained result is `−K⁻¹ v_free`. If it lies outside the disk, solve
`(K + eta I)j = −v_free` with eta≥0 and `||j|| = mu*lambda_n`. GPU uses a direct
2×2 inverse and 64 finite bisections; `||v_free||/radius` is a feasible upper
bracket for SPD K. Apply the resulting world tangent impulse at the same common
point as the normal impulse. This is isotropic maximum dissipation at fixed
normal impulse, not independent component clamps. The world result is invariant
to tangent basis rotation within the retained numerical gates.

Sticking means zero relative tangent speed **at the frozen pre-projection
velocity contact point** when the unconstrained result fits the disk. Sliding
lies on the disk and opposes the final tangent speed. No velocity normalization
is needed near zero speed. For an incline-supported sphere, contact sticking
permits rolling acceleration and does not mean that the COM stays stationary.

Normal and tangent updates alternate in canonical order for 1–64 sweeps (default
32). A shrinking normal impulse immediately shrinks its tangent disk. Original
normal complementarity must meet its unchanged speed residual budget. Tangent
fixed-point residual `||K(j−j_opt)||` must be ≤`1e-9*(1+max initial tangent speed)`;
cone excess must be ≤`1e-12*(1+mu*lambda_n)`. Nonconvergence, invalid iterates or
kinetic-energy gain reject the complete body candidate. Coupled Coulomb/restitution
iterations are not a guaranteed globally convergent optimizer for every admitted
input combination. No silent inelastic or CPU fallback is used.

## Projection limit and timestep evidence

The retained G04a projection translates COMs after the velocity solve and does not
re-solve velocity constraints at the shifted surface contact. Therefore exact
post-projection surface no-slip is **not** qualified. This is a measurable limit,
not hidden by matching the CPU reference. For the one-sphere/fixed-floor trajectory
with resting slop s, gravity g and zero normal speed after each response, the
frozen midpoint lever is `radius − (s + 0.5*g*dt²)/2`. The actual surface slip
after projection is consequently `omega_z*(s + 0.5*g*dt²)/2`. The four-timestep
suite compares this independently derived prediction with GPU observations using
the existing component gate.

At 30/60/120/240 Hz, the radius-0.5 trajectory's measured surface slips are about
−0.00781824/−0.00196187/−0.000500968/−0.000135943 m/s. The independent CPU trajectories
also match. These are specific scene observations, not universal error bounds.
Rotational position correction or velocity re-solving after projection requires
separately scoped work.

The first 60-Hz live comparison failed its unchanged `abs(high surface slip)<0.001`
m/s gate: measured slip was −0.00341857563 m/s for radius 0.35. That failure and
diagnostics are retained. The qualified 60-frame review uses four 1/240-second
physics substeps per frame and keeps that gate. It is labelled near no-slip
rolling. This changes the review's supported timestep profile, not the solver
law or the acceptance tolerance.

## Independent qualification and checked limits

The CPU reference has separate scalar matrix inertia, a different tangent basis,
spectral diagonalization/eigenvalue disk solve and KKT stopping tests. It never
calls GPU tangent/block helpers. Independent checks beyond that reference include:

- Constructed anisotropic KKT solutions: K eigenvalues 2 and 5, known impulses
  and multiplier 0 or 7, rotated bases, exact guard preservation.
- Sphere/floor closed impulses, angular response and energy loss for mu=0,0.1,1,2
  and restitution 0,0.5,1; near-zero speeds 0/1e-12/1e-8 m/s.
- Exact zero-friction G04a body/report equivalence at 30/60/120/240 Hz;
  separating contacts and repeat calls without normal impulse apply no drag.
- Incline stick/rolling versus slip at mu=0.6/0.02, analytic torque/threshold and
  timestep-scaled impulses. The original analytic fixture's torque sign error was
  corrected from r×J without changing the GPU/reference implementation.
- Anisotropic off-center coupled normal/tangent cases, rotated frames, reversed
  slots and alternate bases, closed momentum and velocity-only angular momentum.
  These converge in seven sweeps and reduce normal impulse as the disk shrinks.
- Shared-body contacts, one-second trajectories at four timesteps, full 64-contact
  storage, capacity/overflow and populated-history/body/force rollback.
- Invalid/nonfinite coefficients, corrupt identities/geometry, stale poses and
  coupled iteration exhaustion and positive-friction restitution energy-gain
  rejection. The zero-friction CPU reference now propagates original normal
  rejection codes; its missing error-status copy was reproduced and corrected.
  Original G04a exact touching and signed one-ULP
  boundary fixtures are run without changes.

Allocation limits remain 256 bodies, 64 shapes and 64 response contacts. G04a's
finite guards remain: dt 1/240–1/30 s, e [0,1], dynamic mass [0.1,100] kg, principal
inertia [1e-4,1000], COM/linear/angular components ≤1000/20/10, shape sizes
[0.05,10] m, depth/COM shift ≤0.25 m, quaternion norm error ≤1e-10 and accumulated
normal impulse ≤1e4 N·s. Those admitted guard ranges are not all-combinations
accuracy/convergence claims. Actual friction fixtures use masses 1–3 kg,
radius 0.25/0.35/0.5 m, isotropic and the documented anisotropic inertias, and
the listed coefficients/timesteps. Extreme mass/size/conditioning and arbitrary
dense stacks are unqualified.

Additional error codes: 62 invalid material/basis; 63 tangent convergence;
64 tangent block/cone/numerical failure. Original G04a codes propagate. The body
candidate is committed once, after all response/projection/redetection checks.
Integration, commands, orphan pruning and explicit history publication are
separate commits and are not rolled back by response failure. Failed impulse
diagnostics are scratch values. G03c history remains correspondence only.

## Live review, memory and reproduction

The game-owned `gpu_friction_review.mojo` runs two sequential GPU worlds for
60 rendered frames: identical sliding/spinning spheres, mu 0.02 versus 0.8,
four physics substeps per frame. It checks every substep cone/energy bound and
compares all 120 frame body states and final-substep energy/contact reports
against post-render independent replay. Trails/markers come from GPU observations.
Fixed bodies/storage stay unchanged and Vulkan validation must report zero errors.
Rendering uses staged snapshots, with no direct CUDA–Vulkan or measured DMA claim.

G04b adds 1,080 explicit buffer bytes (130 Float64 tangent entries plus five stats)
at capacity 64. Maximum world/default history/G04a/G04b totals 1,713,480 bytes;
the two-world review totals 3,426,960 bytes, below 16 MiB. Context, host, compiler
and rendering allocations are additional.

```sh
python3 scripts/qualify-friction-response.py test --slot-confirmed --build
python3 scripts/qualify-friction-response.py packaged --slot-confirmed --build
python3 scripts/qualify-friction-response.py demo --slot-confirmed --build
```

Use the unchanged pinned Mojo/MAX environment. Exclusive sequential execution
requires H3 paused, one native compiler thread, 180-second compile and 30-second
numerical/render deadlines, plus 32 GiB available-memory reserve. Temperatures
are observations; retired cutoffs remain inactive. No settings, drivers, hardware,
toolchains, SDK/campaign/assets or H3 launchers change.

Receipts: `build/physics-g04b/{test,packaged,demo}-qualification.json` and
`games/yo-frankie/build/frankie-gpu-friction-rendered.json`.
Evidence, failures/diagnostics, final source, regressions, preservation and cleanup:
`/home/user/Documents/Codex/2026-10-12/task/physics-g04b-20261013/verification.json`.
Stop at this bounded checkpoint. Warm starting, separate static/dynamic materials,
new shapes, parallel solving, broader static support and performance work remain pending.


## Subsequent stability investigation

The above G04b implementation and both review baselines remain unchanged. A
separate [position-first stability owner](STABILITY.md) now removes its dt²
anchor-slip term and passes the original 60-Hz surface-slip gate without changing
the scene or increasing substeps. The corrected owner remains experimental and
opt-in; retained slop, integration timing and cold incline dissipation still
limit exact surface sticking and continuous-work accuracy.


The recommended experimental demo now uses that corrected owner through
`recommended.GpuPhysicsResponse` and `qualify-gpu-physics.py demo`, with one
60-Hz physics step per rendered frame. This document's original G04b owner,
240-Hz demo and receipts remain unchanged regression evidence. Recommendation
of the experimental path does not change the ordinary SDK or campaign behavior.
