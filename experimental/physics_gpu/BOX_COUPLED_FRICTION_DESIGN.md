# Predeclared targeted coupled-friction numerical policy

Preserve GpuBoxResponse and all historical64/96 results. Add a separate opt-in
GpuCoupledBoxResponse, if native qualification succeeds. The contact law stays
minimum-norm unilateral normal pressure plus point-wise non-associated circular
Coulomb maximum dissipation. No friction coefficient/material, geometry, gate,
substep, warm start or global scheduling change. Original failure is never relabeled.

Exact target: BOX_INTERACTIONS id3/seed17/variant0, mass2, collision half extents.5,
supplied diagonal inertia4/3 (the original factory passes half_extents*2 to the
half-extent inertia API), upper x.03, v(.3,0,.05), mu.2, gravity9.81, dt1/30.
Retain that prescribed inertia even though it is not uniform-density unit-cube
inertia. The original96 fails with normal3.69438989357e-7/tangent8.53302728823e-6,
gates1.327e-9/1.30413812651e-9 and complete response-entry rollback.

Independent proof: build the12DOF rigid-body Jacobian from input corner midpoints
and supplied tensors. It reconstructs GPU velocities and normal Gram matrices,
not from CPU/GPU agreement alone. A closed-form common slide v'=v-mu*g*dt*v/|v|
with floor/upper normal loads1.308/.654 and pressure moments gives zero angular
velocity, positive minimum-norm pressure, circular Coulomb KKT (floor sliding,
upper at limiting static friction), unchanged residual/cone budgets and dissipative
energy. Keep original histories, active-point data, conditioning and discarded
finite-difference/inertia diagnostic probes. Strict-boundary translation timing
and unreached ledge events remain separate unresolved coverage.

## Distinct bounded solver policy

Within each current patch, assemble the coupled normal/tangent effective-mass
matrix (normal4,tangent8 maximum). For tangent vectorx, solve normal pressurep(x)
with the existing cached PSD minimum-norm active-subset operators. Find roots
x_i-disk_min(Ktt_ii,vt_i-Ktt_ii*x_i,mu*p_i(x))=0. This is the same Coulomb KKT
law, with pressure/tangent feedback solved together instead of alternating a
frozen pressure block and independent tangent coordinate visits.

Use analytic implicit disk derivatives and active-normal operator derivatives.
Sticking derivative is -K^-1. Sliding derivative is
-A+(A*d)*(d^T*A)/(d^T*A*d), radius derivative A*d/(d^T*A*d), A=(K+eta*I)^-1,
d=j/r. This avoids finite-difference rank noise and tiny-radius squared underflow.
Solve at most8 local Newton corrections with at most16 halving line-search trials
each. Rank-aware8x8 elimination uses256 binary64eps relative to Jacobian scale;
null directions use a least-norm correction. Internal impulse root target is
64eps*(1+max impulse), a representation-level target, not a relaxed physical gate.

Accept accelerated patch proposals only if finite, bounded, nonnegative pressure,
per-point cone-feasible at the original1e-12*(1+radius) gate and valid body profile.
Otherwise use one explicitly counted legacy normal/tangent patch update. There
is no CPU or larger-budget fallback. Private rejected Newton trials never publish.
All patch attempts/evaluations/Jacobians/backtracks/Newton corrections/fallbacks
are exposed by a work report; counters separate extra work from outer sweeps.

For mu>0 execute the complete explicitly requested outer budget (1..64 under64,
1..96 under explicit96); do not silently stop early and then change a numerical
gate. This deliberately trades more work for a separate numerical policy. For
mu0 use the unchanged legacy velocity solver; no-contact remains zero work.
Final normal/tangent residual, energy, cone, unreduced depth/normal, profile and
transaction publication checks remain original. No policy promises convergence
for all admitted bodies/mass ratios/loads. Basis rotations must preserve physical
results at the original analytic/state gate.

## Required evidence and resource boundary

Native GPU one-step original rejection and corrected opt-in result; independent
closed-form pressure/velocity/energy and reduced-system residuals; basis0/45/90,
Coulomb boundary/interior/zero-radius and derivative finite-difference checks;
source/precompiled targeted fixtures and affected70 interacting trajectories with
independent CPU replay; original fixture suites, sphere APIs/review, engine/game,
policy failures and preservation against final fingerprints. Any new opt-in
failure is retained, not solved by changing inputs or gates. Record synchronized
response wall time as scoped host/API work, not bare-kernel or real-time evidence.

Native compiler one thread/180s, each run30s, exclusive slot,32GiB reserve,
matched pins/normal settings/H3 pause. No installs, driver/power/settings changes.
Stop at this targeted correction checkpoint and report remaining limitations.
