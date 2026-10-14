# Bounded box response: design and acceptance gates set before qualification

This is a separate experimental owner; the qualified sphere, sphere/OBB,
history, recommended response, island and sleep paths remain unchanged.
The detector's binary64 conditioning limits continue to apply. In particular,
an almost flat clipped corner does not provide a uniformly accurate solver anchor.

## Contact representation and solver treatment

Reduce each current patch to at most four distinct footprint points. Obtain the
convex projected footprint order and choose the maximum-area inscribed four-point
polygon, with canonical lexicographic tie breaking. Preserve a triangular patch;
line/point representations use their farthest pair/single point. Coalescing and
collinearity use the existing scale-aware representation resolution. This avoids
using all up-to-nine clipped corners as independent equations and tends to omit
ill-conditioned near-collinear edge intersections. The reduced footprint does not
necessarily contain every original extreme: validate all unreduced vertices after
solving, and reject an approaching discarded vertex rather than silently adopting
an invalid reduced contact constraint.

Four coplanar normal constraints still have rank at most three. Treat the normal
patch as a positive-semidefinite unilateral block, not an invertible 4x4 system.
Enumerate at most 16 active subsets, use a scale-aware spectral pseudoinverse,
check feasibility/complementarity, and select the minimum Euclidean-norm feasible
nonnegative impulse. This resolves symmetric pressure gauge freedoms without
artificial compliance or a fourth independent angular DOF. Numerical null-space
classification is tied to binary64 epsilon; infeasible/unresolved systems reject.
A scalar CPU elimination/null-space reference must independently check the block.

Run serial patch sweeps from cold impulses. After a patch normal block, use the
existing one-coefficient circular Coulomb disk maximum-dissipation law at each
selected point, with both bodies' world inverse inertia and a common witness
midpoint. Normal/tangent sweeps remain bounded to 1..64. No warm start, history
impulse reuse, graph scheduling, broad phase, sleep or parallel solver work.
At most 64 selected response points and 16 patches are admitted in this first
owner; existing 256-body/64-shape and physical response profile limits stay.
Same-body and static/static pairs are not dynamic constraints; mixed sphere
contacts are explicitly rejected by this box-only response owner.

## Position, velocity and transaction sequence

Freshly detect committed box patches. Copy all body fields to private scratch.
Use cold, mass-weighted COM translation to the existing 1e-5 m slop, without
changing orientation or velocities. Rebuild box geometry at the privately
projected pose and reduce those fresh patches for the velocity solve. Reject
new dynamic pair topology created by correction, geometry/profile/capacity
failures, nonconvergence and forbidden energy gains. Validate unreduced current
patch depths and normal velocities before one authoritative body commit.
Force/torque fields and fixed bodies remain bitwise unchanged by response.
Integration/commands/detection publication are earlier separate transactions;
a failed response preserves the state at response entry, not pre-integration state.
Common-point equal/opposite impulses conserve linear/angular momentum during
velocity solving. COM projection is artificial position repair; measure its
potential-work/orbital effects explicitly rather than claim their conservation.

## Predeclared designated gates

Use the existing physical profile: dt [1/240,1/30], dynamic mass [0.1,100],
inertia [1e-4,1000], coordinates <=1000, linear/angular components <=20/10,
box half extents [0.05,10], offset <=10, shallow depth/COM correction <=0.25.
Coefficient mu [0,2], restitution [0,1] with the existing -0.2 m/s bounce threshold.

Per response, unchanged numerical gates are: normal complementarity residual
<=1e-9*max(1,1+maximum initial normal speed); tangent fixed-point residual
<=1e-9*(1+maximum initial tangent speed); Coulomb cone excess
<=1e-12*(1+mu*normal impulse); velocity-stage kinetic energy increase
<=1e-9*(1+energy before); post-correction depth <=1e-5+1e-9 m.
No failed gate will be widened to claim stability.

Analytic impulse/state comparisons and closed velocity-stage linear/angular
balance: 1e-10*(1+absolute expected component). Centered flat-floor loading must
have equal corner pressure and zero resultant spurious torque at that gate.
Fixed bodies, force/torque accumulators and failed authoritative transactions
must be byte-identical. Duplicate/redundant point representation and near-parallel
pressure/state checks must supplement the independent block reference.

Designated rest trajectories: one centered cube and two/three centered cube
stacks, 2 s, gravity (0,-9.81,0), restitution zero, dt 1/30,1/60,1/120, and
1/240 for refinement; full 64 velocity/position sweeps. After initial settling,
COM drift <=1e-4 m (ten existing slop units), angular drift <=1e-3 rad,
post-response speed/angular jitter <=1e-3 m/s or rad/s, penetration at the
unchanged per-frame gate, and no unsupported energy/work gain. Measure energies,
gravity work and projection potential work separately. Record lower 16/32
sweep acceptance/residuals rather than silently change the budget.

Other required bounded fixtures: offset support, face and edge impacts,
frictionless and frictional floor motion, shared dynamic bodies, symmetric load,
closed impulse conservation, near-coplanar geometry/reduction, tiny activity,
invalid/stale/capacity/iteration/energy/topology rollback. Source/precompiled actual
GPU suites, an independent CPU matrix/block/trajectory reference, retained
regressions and a short detection-and-response diagnostic are required.
A designated failed stack/conditioning/convergence gate is a stability blocker;
report its exact timestep/budget/state and do not claim general stable stacks.

One-thread compilation, finite 180 s compile/30 s run guards, one exclusive
native/GPU workload, 32 GiB reserve and temperature observation only remain.
H3 stays paused. Stop at this response checkpoint before further features.
