# Bounded experimental multi-point box response

`experimental.physics_gpu.box_response.GpuBoxResponse` is a separate box-only
response owner. It keeps the qualified sphere/sphere, sphere/OBB, recommended
response, history, island and sleep owners unchanged. No normal SDK or Yo Frankie
campaign adoption, general stack stability or performance claim is made.

```mojo
from experimental.physics_gpu.box_response import GpuBoxResponse
var response=GpuBoxResponse(velocity_budget=96)  # explicitly opt into extended policy
# Create bodies/shapes through response.detection.world, as in G02/G03.
_=response.detection.world.bodies.step(1.0/30)
var report=response.resolve(1.0/30,velocity_iterations=96,position_iterations=64)
response.close()
```

The default policy remains 64 maximum velocity sweeps, with 32 requested sweeps
unless the caller supplies a budget. The distinct constructor policy 96 admits
up to 96 requested velocity sweeps; position sweeps remain bounded to 64. Both
use the same residual, energy, cone, penetration, profile and publication gates.
An invalid budget or nonconvergent frame rejects before authoritative body writes.
There are no substeps, changed scene inputs, soft constraints or hidden fallback.

## Representation and contact law

Use the current detection patch's projected convex footprint. Select a maximum-
area inscribed quadrilateral, keep a triangle, or choose a farthest line/single
point, restoring canonical midpoint order. At most four selected points represent
one pair. Near-collinear clipping corners need not become independent constraints.
All unreduced current points are still checked after solving; approaching omitted
vertices reject the candidate rather than silently accept an invalid reduction.
A reduced footprint is an approximation to the full polygon and is not promised
to support every load center or rotational state of the original patch.

Coplanar normal constraints have rank at most three. Each patch solves its
positive-semidefinite unilateral normal block by at most 16 active subsets,
a scale-aware spectral pseudoinverse, feasibility/complementarity checks and a
minimum Euclidean-norm nonnegative impulse choice. No fourth invertible normal
DOF or artificial diagonal regularization is introduced. Symmetric flat-face
loading gives symmetric pressure and zero resultant spurious torque. Degenerate
or unresolved blocks reject. The eigen null-space cutoff is 256 binary64 eps
relative to the largest scaled eigenvalue; stopping rotations use 32 eps.

Operators are derived afresh from the privately projected pose each resolve and
reused only within that call. This removes repeated factorization of an unchanged
matrix during sweeps. It is not warm starting, persistent factor/contact reuse,
impulse history or a throughput qualification.

Cold serial normal patch blocks alternate with the existing per-point circular
Coulomb disk law, with one uniform coefficient mu in [0,2]. Tangential impulse
minimizes `0.5*j^T*K*j + v_free^T*j` subject to `||j||<=mu*lambda_n`, using both
bodies' world inverse inertia. Normal and tangent impulses act at a common witness
midpoint with equal/opposite forces and lever-arm torques. There is no per-axis
clamp, separate static/kinetic coefficient, rolling resistance or warm start.
Restitution retains the existing incoming speed threshold -0.2 m/s and range [0,1].

## Projection and publication

Fresh current box geometry precedes a private body copy. Mass-weighted COM
translation projects shallow linearized gaps toward the existing -1e-5 m slop,
with 1e-9 m residual allowance and maximum initial depth/shift 0.25 m. Orientation,
velocities and force/torque fields do not change during projection. Geometry is
rebuilt at the private projected pose before point reduction and velocity solving.
New dynamic pair topology created during projection rejects. After the solve,
validate current depths and normal/restitution targets at all unreduced points,
profile, complementarity, cone and kinetic-energy budgets before one body commit.

Response preserves fixed-body and pending force/torque bytes. Integration, body/
shape commands and the detector's orphan reconciliation remain earlier separate
transactions. A failed response preserves state at response entry; it does not
roll back the preceding integration. Public detection-frame publication is a
separate explicit `response.detection.detect()` call. Impulse/operator/residual
buffers after failure are scratch diagnostics, not committed simulation inputs.
`residual_history()` is read-only diagnostic output from the last attempted solve.

Common-point impulses conserve closed velocity-stage linear/angular momentum.
COM projection is artificial position correction: potential/orbital effects are
reported separately, not claimed conserved. Trajectories measure gravity energy,
projection potential work and normal/friction kinetic dissipation independently.

## Convergence counterexample and distinct policy

The original three centered m=2 cubes, fixed floor, gravity9.81, dt1/30 and 64
sweeps remain an explicit failing configuration. On the first response, the normal
residual is about 2.19977e-9 versus the unchanged 1.327e-9 gate; all body bytes roll
back. This is a reproducible convergence limit, not a corrected historical pass.

An independently solved 80-digit Decimal translational Delassus system is
`W=[[.5,-.5,0],[-.5,1,-.5],[0,-.5,1]]`, with exact equilibrium impulses
`(6*g*dt,4*g*dt,2*g*dt)`. Its spectral condition number is about 16.394. Scalar
Gauss-Seidel and GPU/independent CPU residual histories agree with
`r_k=.5*g*dt*.75^(k-1)`. Uniform mass scaling changes force impulses but not velocity
convergence; load and timestep scale residuals as predicted. First passing sweeps
at 30/60/120/240 Hz are 66/64/62/60 for the unchanged scene and gate.

Explicit96 passes the original scene at sweep66: two extra full patch passes,
about3.125% additional visits for that first step. Its worst-case budget permits
50% more visits than64; this is extra work, not a speedup claim. The same two-second
30-Hz rest scene then passes physical drift/jitter/penetration/energy-work gates.
Baseline64 is qualified for these centered three-cube rest fixtures at 60 Hz and
higher; at 30 Hz it rejects safely. One/two centered cubes pass the tested30–240 Hz
range with64. Requested16/32 limits and insufficient budgets remain explicit
nonconvergence configurations. Neither policy guarantees all admitted geometry,
mass ratios, stack heights, frictional stacks, perturbations or impact combinations.

## Gates, qualification and limits

The original gate document [BOX_RESPONSE_DESIGN.md](BOX_RESPONSE_DESIGN.md) is
preserved unchanged. Response gates remain normal complementarity
`1e-9*max(1,1+max initial normal speed)`, tangential fixed-point
`1e-9*(1+max initial tangent speed)`, cone excess `1e-12*(1+mu*lambda_n)`, and
velocity kinetic-energy gain `1e-9*(1+energy_before)`. Position/post gates remain
`1e-5+1e-9 m`. Analytic/state and closed impulse balance comparisons use
`1e-10*(1+abs(expected))`; failed body/metadata/force transactions are byte checked.
Rest fixtures are two seconds with drift <=1e-4 m, angular drift <=1e-3 rad and
settled speed/angular jitter <=1e-3, over30/60/120/240 Hz without changing inputs.

The inherited physical response profile is dt[1/240,1/30], mass[.1,100], inertia
[1e-4,1000], coordinate components<=1000, linear/angular components<=20/10, quaternion
norm error<=1e-10, half extents[.05,10] and local offset<=10. This owner admits up to
16 dynamic patches/64 selected points over 256 bodies/64 shapes. Static/static and
same-body pairs are skipped; any sphere shape is rejected explicitly. These are
bounded admission limits, not guaranteed convergence for every combination.

Box detection's binary64 ambiguity/conditioning limits remain. In near-parallel
response tests, any different GPU/CPU face convention must independently satisfy
a representation-scale SAT gap tie and normal alignment before the CPU reconstructs
that convention from input corners. No device contact normal/point/solved body is
used as an expected value. The original mismatched-face failed comparison is kept.
This conditional reference does not claim a unique normal below SAT evaluation
resolution. General adaptive exact predicates and precision-independent contacts
remain outside this checkpoint.

Actual GPU source/precompiled groups cover analytic pressure/torque, centered and
offset support, face/edge restitution impacts, shared closed-body momentum/energy,
friction, duplicate/redundant normal constraints,32 seeded near-parallel cases,
invalid/profile/stale/capacity/iteration/topology/energy/closed and byte-rollback
contracts,16 patches/64 points, rest/load/mass/timestep convergence, two-second
frictionless/frictional motion and a 12-step explicit96 diagnostic. Friction stopping
distances match an independent discrete Coulomb velocity sum within 2.5e-11 m and
show first-order convergence toward the continuum stop distance. No broad stack
benchmark, long-duration, mesh/joint, sleep or parallel feature is qualified.

Error codes: 110 capacity;111 configuration;112 geometry;113 unresolved normal
block;114 velocity/friction convergence;115 depth/position/shift;116 post geometry/
velocity;117 physical/mixed-shape profile;118 kinetic energy;119 new topology;
120 tangent/cone validity. Existing lifecycle/detection errors still propagate.

Reproduce `python3 scripts/qualify-box-response.py MODE --slot-confirmed`, where
MODE is `test`, `packaged` or `demo`; each test group has its own 30-s guard. Compiler
builds use one thread and 180-s guards, exclusive slot,32 GiB reserve and temperature
observation only. H3 stays paused. Final receipts and preservation/cleanup are in
`build/physics-box-response/verification.json`; the partial checkpoint, original64
failure and earlier timeout/adapter failures are retained separately.
