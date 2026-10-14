# Seed-61 bounded coupled-friction rank correction

The retained original failure is interacting case52: id5, seed61, variant0,
30 Hz, explicitly64 velocity sweeps. At frame7 the upper body's x velocity was
2.7262341470843476e-10 on GPU versus1.249498046804347e-10 in independent CPU replay.
The difference1.4767361002800006e-10 fails the unchanged1e-10*(1+abs(reference))
physical-state gate. Earlier maximum absolute state differences were5.02e-16.
The original63/70 local-complete,62/70 fully qualified checkpoint is historical;
its coverage, receipts and failed trace are preserved.

## Reduced diagnosis

Test-only instrumentation captures the first spurious rank at frame7, sweep0,
floor patch0. The coupled sticking Jacobian's three leading singular values are
2.45012,2.45012,1.41177; the fourth is3.47e-16. Independent corner geometry and a
scalar rigid-body Jacobian reconstruct the operator to4.44e-16 and also give rank3.
All pressure is positive and every disk is strictly interior, with minimum margin
0.0327. The original256eps relative cutoff is4.42e-14 on this matrix.

Fixed-column row elimination divides by a weak third pivot0.00451854 and amplifies
null-space roundoff. It then accepts a false fourth pivot7.07906e-14. Its Newton
correction has magnitude0.00939338, while an independent SVD least-norm correction
has magnitude1.96e-11. The immediate physical correction difference is only4e-18:
the large extra component is predominantly an internal impulse null direction.
It nevertheless changes the bounded Newton path and the final physical state.

The full anchored sticking system has rank12 and fixes all12 body velocity
components. Contact impulses have internal null directions; physical velocity
is unique. Independent full sticking kinetic-metric projections for exactly64
sweeps reproduce the saved CPU physical velocity to3.86e-16. The original GPU
error against this independent result is1.477e-10. Positive normal impulses,
strict Coulomb margins, floor/upper loads1.308/.654 and decreasing kinetic energy
are independently verified. Nonunique impulses therefore do not invalidate the
physical-state comparison contract. No assertion or accuracy gate changes.

## Narrow correction and evidence

Only `coupled_friction_math.linear8` changes: choose the largest pivot in the
remaining row/column block, retain the column permutation, compute the same
least-norm null-space projection, then restore original coordinates. This avoids
roundoff amplification from weak fixed-order pivots. The original256eps threshold,
eight local Newton corrections, sixteen halving trials, outer64/96 requests,
Coulomb/profile/energy/residual gates, projection policy and opt-in API remain.
No compliance, regularization, warm start, extra sweeps/substeps or performance
work is introduced. Pivot search is bounded by the existing8x8 size.

A device regression uses the exact captured matrix with independent NumPy SVD
gold and row/column permutations. It fails the original helper (rank4), then
passes the corrected helper (rank3). An instrumented candidate passed the exact
15-step trajectory before the production edit. Final source/precompiled checks
and the affected70-case matrix are recorded separately against the final source
fingerprint. CPU replay retains independent geometry, unit-response assembly and
spectral disk evaluation; independent SVD and kinetic projection provide proof
beyond CPU/GPU agreement of elimination methods.

Evidence: `build/physics-seed61/{localization,reduced-diagnosis,physical-proof}.json`,
retained original source/executables and probes in that directory, and final
`build/physics-seed61/final/{COVERAGE.md,verification.json,SHA256SUMS}`.

Final source and fresh precompiled API runs each complete all70 cases within
their unchanged guards. Records and trace arithmetic are identical. Each path
now qualifies63/70 full trajectories (previously62/70). The seed-61 fixture
completes15/15 steps with maximum state-error gate ratio4.39348e-6 and frame7
physical velocity error2.606e-16 versus the independent64-sweep projection.

The analytic0/45/90-degree target and source/precompiled SVD rank/permutation,
conditioning, nonfinite/configuration, Coulomb/energy and exact rollback gates
pass. All original96-sweep rejection records remain. At basis0 the corrected
prototype uses505 Newton corrections and2707 residual evaluations for the same
96 outer sweeps; the original437/2066 counters remain historical. Measured
synchronized host/API target wall time across both paths/bases is1.01–1.63s;
these scopes are not GPU-only or an efficient replacement qualification.

The two frictionless64 convergence rejections, translated strict binary64 boundary
failure and four ledge scenes that never detached remain separate limits. This
is a bounded correctness fix, not general stack stability or an efficient solver
replacement. Original Atlas APIs, baselines, SDK/campaign, pins and settings stay
unchanged; the coupled prototype remains opt-in.
