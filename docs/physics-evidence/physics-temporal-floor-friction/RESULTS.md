# Temporal planar-floor friction: stopped on unloaded continuation

Implemented separate opt-in GpuTemporalFloorFrictionAdvance, preserving the qualified frictionless temporal owner and qualified frozen block verbatim. No default, precision, warm-start, compression or full engine/controller change. Candidate is **not qualified or promoted**: first analytic sliding/stopping checks pass, but an expected supported zero-normal-load continuation after impact rejects. The first substantive failure stopped all subsequent native work without tuning or numerical-gate/fixture changes. No benchmark ran.

## Supported schedule proposed and implemented for qualification

One dynamic axis-aligned box, optional fixed planar box floor, near-zero physical angular motion/no applied contact torque, constant force/normal acceleration<=0, strict positive-pressure certificate. Uniform oblique slip is allowed; tangential acceleration must be collinear with existing slip. Rest can remain stuck under the circular threshold or start along a super-threshold force. Turning slip, a stop requiring reversal under opposing super-threshold force, rotation/torque/tipping, malformed geometry and exhausted budgets reject atomically. Reversal is not implemented.

Four fixed1/120s bases per1/30s macro. Up to6 segments per base; impact admissions<=4; stopping/onset counters separately<=4. Constructor can only lower stop/segment caps for transactional tests. A physical stop root is computed at actual segment entry, before any full-interval kick: t_stop=speed/(mu*g_eff-F_parallel/m) for positive deceleration. Event roots within64eps*(1+remaining) of a base endpoint normalize to that actual endpoint; otherwise split at the root. This avoids microscopic remainder scheduling while retaining every independent accuracy gate. The initial unexecuted compile/binary and pre-native review are saved. No resulting velocity, spin or position is clamped.

Actual segment duration controls both external half-kicks and normal budgets. Start group: reset normal AND tangent impulses, call qualified block twice using delta updates, then unforced drift at the resulting midpoint physical velocity/angular state. End group: second external half-kick, reset both impulse components and call twice. Final4 calls retain both components of the last group; no new budget. Impacts use physical quadratic TOI, completed event-sized external force integration and frozen incoming restitution target. Subsequent support resets the impact group, so its normal impulse is never a later friction bank. Body/force/torque and committed episode/last-state publication remains the unchanged qualified atomic commit, with prior registry commands committed earlier.

These schedule additions preserve the approved macro10um/0.1mm/s/10urad/0.1mrad/s and one-second0.1mm/1mm/s/1mrad/1mrad/s bounds plus lever tightening; no accuracy relaxation is needed for stopping splits. New stopping/onset event bookkeeping and rejection states are actual contract additions. Existing four bases, impact cap, segment ceiling, numerical/physical gates and circular law stay unchanged. The candidate's full supported domain remains unqualified because the failure below interrupts validation.

## Verified completed stages

12 independent analytic fixtures ×4 valid mass/inertia/geometry variants × point orders0/5/11/23 =192 source and192 fresh-package records, byte-identical. Tests include axial/oblique sliding distance and speed, stops at¼/½/end first base and middle of last base, below-threshold static holding, above-threshold onset, stopping under parallel and antiparallel sub-threshold force, initial zero normal budget, andmu0 parity. Stopping times are checked against analytic roots and distances u²/(2*deceleration), not CPU/GPU agreement alone. Momentum includes actual external force/gravity and accumulated normal+tangent impulse; energy includes constant-force work and analytic spatial Coulomb dissipation. Per-group original disk/normal/cone/profile/kinetic gates are enforced by the unchanged frozen block. Actual spin/orientation are checked independently, never suppressed.

Maximum first-stage errors:

- position_error: 3.87895961445e-18
- velocity_error: 1.24158143986e-16
- spin: 8.30938782087e-17
- angle: 1.49960737497e-18
- momentum_error: 7.17533971442e-15
- energy_error: 5.77315972805e-15

Next independent source gate:37 recorded rows,36 successful before the failure. Variant0 completes all30 impact/protocol cases, including oblique e=0,.5,1; zero-normal-load impact;mu0; unsupported turning/torque/tilt; pressure margin/boundary rejection; stop-cap and reversal rejection after private progress from nonempty episodes; segment cap; and TOI exhaustion. Variant1 completes6 gravity-impact rows and fails on its first zero-gravity impact. Subsequent source variants, package impact/protocol tests, genuine repeated one-second frames and remaining lifecycle identity checks were not run. The fresh30-module package has no optimized/warm/packed owner imports.

## First substantive failure and smallest saved reproducer

m=.1kg, I=(.01,.02,.025)kgm², half=(.25,.5,.75)m, floor top0, initial COMy=.502m, v=(.3,-1,.4)m/s,mu=.2,e=0, gravity/force/torque0. Physical impact occurs at0.0020000000000000018s, with one TOI admission. The coupled impulse correctly leaves tangential velocity(.18,.24)m/s. Floating arithmetic leaves a small upward normal velocity5.551115123125783e-17m/s.

The remainder enters support because touching is true and the normal-speed tolerance is satisfied. Both normal and tangent group arrays are correctly reset to ALL ZERO. The compression-specialized frozen block then requests

    N=m*(beta-v_n*)=.1*(0-5.551115123125783e-17)
     =-5.551115123125783e-18kgm/s.

It rejects block404, propagated as owner1304. Three block calls were attempted: two at impact, then the failed fresh support call. Only0.002s of the macro was advanced privately. This is an adapter admission failure, not double friction, impact-budget reuse, a stopping error, tipping, turning, a compiler failure or an event-count oracle mismatch.

Saved last-block inputs permit an independent zero-impulse witness without a native replay. All four gaps are0. Normal point velocities are4.683753385137379e-17 twice and6.418476861114186e-17 twice: all opening. Setting normal/tangent impulses0 satisfies the original unilateral residual with residual0, zero-radius maximum-dissipation disks and cone gates, preserves actual linear/angular velocity, and changes kinetic energy0. There is no requirement to close an opening/unloaded row at beta0. The owner incorrectly applied the closed/compressive reduction instead of dispatching that unilateral continuation.

The saved after-state's full23 dynamic-body words are bit-identical to the initial factory state; the complete body-registry metadata equality assertion ran. Full-body/force/torque and committed episode/last-state byte assertions passed in the earlier expected-rejection cases, including failures after private progress from an already committed episode. The unexpected-code test branch does not dump/assert those complete before-body/episode buffers specifically for this failure, so their bytes are not claimed separately measured here. Source inspection proves publication is skipped: unchanged commit_temporal returns before every current-body/episode/last-state write when summary0!=0. Full last-block input/output and private candidate state are retained; no duplicate diagnostic replay was run. Failed-row position/velocity error fields remain initialized0 because no accepted-state analytic branch ran; those zeros are not a passing accuracy claim.

Minimal future correction proposed, **not applied**: teach the separate temporal adapter to dispatch zero-demand/opening contact to a zero-normal/zero-tangent unilateral continuation, validating unchanged actual row/gap/energy gates and preserving velocity/omega. Call the compression-only qualified block only in its supported compressive domain. Do not edit the qualified frozen block, force normal velocity to0, clamp spin, loosen gates or borrow the impact load. Requalify with near-zero/opening and zero-load impact cases plus explicit full-byte unexpected-failure rollback checks before proceeding to trajectories/lifecycle. No broader solver or performance claim follows from this negative result.

Preservation: 18,460 protected hashes, all5,901 asset/save identities, 17 campaign sources and119 other source/lock hashes unchanged. Pinned Mojo1.2.0.dev2026092905 / isolatedMAX26.7.0.dev2026092905 unchanged. Minimum available memory111.537GiB; final113.574GiB; reserve32GiB. One execution slot, single-thread builds, one-CPU precompile, finite180s build/30s native guards. Ten added owner buffers /50,168 explicit bytes. Hardware/driver/power/security/profiling permissions/defaults/precision and unrelated dirty work unchanged; H3paused; no counter retry; dynamic spills/stalls unmeasured.

Sealed stop: GPU idle, no owned jobs, no timing. Evidence: verification.json, post-failure-audit.json, first source/package records, failed probe row/log/telemetry, full block IO/private candidate, predeclared.json, qualification-plan.json, pre-native-review/source/binary, package/dependency and build fingerprints, primary sources and FINAL-SHA256SUMS.
