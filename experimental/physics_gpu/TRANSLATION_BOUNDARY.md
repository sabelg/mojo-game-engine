# Bounded translated-collision boundary diagnosis

The original strict SAME-TIME translation fixture remains failed. Original
interaction coverage stays **63/70**. This investigation adds a separate resolved
boundary qualification; it changes no production physics, contact slop, physical
state gate, integration policy, coordinate representation or solver budget.

## First difference and exact reference

Original cases35/68 are the closed collision at60Hz, explicit96 sweeps, with
common translation(2,0,1) for case68. Both individual trajectories complete60/60
steps and pass independent response replay, physical state, energy and rollback
gates. Their original and freshly replayed initial/body/response traces are
byte-identical on source and fresh precompiled API paths. All binary64 words are
preserved alongside the original inputs and traces.

The first relative-geometry difference exists in the encoded initial positions:
the translated separation is smaller by exactly2.220446049250313e-16m. The two
encoded initial gaps are0.10000000000000008881784 and
0.09999999999999986677324m. Closing speed inx is exactly1m/s.

At frame5 (six60Hz steps, nominal0.1s):

|Quantity|Original|Translated|
|---|---|---|
|Exact stored-input gap with exact integration|+9.020562075079397e-17m|-1.3183898417423734e-16m|
|Exact gap between saved binary64 centers|+4.440892098500626e-16m|-2.4424906541753444e-15m|
|Evaluated pair-relative SAT gap error|exactly0|exactly0|
|Gap binary64 bits|3cc0000000000000|bce6000000000000|
|First observed contact frame|6|5|
|First observed contact time|7/60s|6/60s|

A standard-library Fraction reference reconstructs the initial dyadic positions,
exact closing motion and all12 precontact integration substeps independently.
Its binary64 substep reconstruction matches saved frame5 center bits. Absolute
position accumulation amplifies the separation difference near zero, but exact
higher-precision motion of these stored inputs already has opposite signs at the
sample. Pair-relative SAT already removes the common origin and is exact on these
two Cartesian gaps. Thus this repro supplies no evidence of a defective SAT or
response calculation. More precise SAT, or simply rebasing these already rounded
inputs, cannot turn the distinct exact stored-input crossings into one event.

The first contact-activation and response differences are both at frame5. The
original left body remains atvx=.5; the translated body has already rebounded to
vx=-.24989963811540725. The unchanged same-time physical state comparison fails by
about5e9 times its gate. No increased tolerance could legitimately equate these
event sequences. The failure is retained, including its strict assertion and
coverage exclusion.

Evidence: `build/physics-translation-boundary/exact-localization.json` (recovered
original binary64/input/response capture), `independent-exact-proof.json`
(independent exact fractions), and `strict-repro/{source,packaged}` (fresh exact
replays). All previous receipts and failed traces retain their hashes.

## Supported numerical contract and separate qualification

Contact classification uses the evaluated binary64 SAT gap: positive separates,
nonpositive contacts. Arbitrary independently rounded translations do not promise
same-observation activation at a near-zero sign boundary. This does not relax any
physical gate. Individual admitted stored-input trajectories still require the
original independent state, residual, energy, Coulomb, depth/profile and rollback
checks. Event times are discrete observations with brackets, not CCD timestamps.

The predeclared test domain is two identical unforced Cartesian cubes of mass2,
half extents.125,.5,2; common translations(T,T/2,-T/4), T=0,±2,±256; zero spin and
transverse velocity; restitution.5, coefficient.2, explicit96 velocity and64
position sweeps. Shape, coordinate and response profile bounds are unchanged.
The eligibility margin2^-36m is an error-envelope statement, never a SAT epsilon.
Exact touching is qualified only for the separately constructed dyadic Cartesian
centers T±h and radii h whose gap is provably exactly0.

All **75/75 source and75/75 fresh precompiled actual GPU fixtures pass**:

- Static45 per path: positive, zero and negative gaps at all sizes/translations.
  Exact dyadic interval signs and independent corner geometry agree. Positive
  gaps preserve the entire body buffer; touching/overlap gives one four-point
  patch, total normal impulse1.5, analytic velocities∓.25, zero spin, conserved
  momentum/angular momentum, and kinetic energy.5→.125.
- Dynamic30 per path: initial gap.107m, both rates30/60Hz, duration.3s. There are
  no false/missed impacts: one creation and one end, first contact4/30s or7/60s,
  bracketed by the previous.1s observation. Exact signs, preimpact motion,
  analytic rebound and subsequent free flight pass. No recontact occurs.
- All450 pair-state observations (900 body states) per path pass independent CPU replay and the unchanged
  translation-normalized physical-state gate. Source/precompiled input, body,
  impulse, result and binary64 archives are identical. Energy/projection work,
  circular Coulomb bounds, depth/residual/profile, accumulator and no-contact
  bytes, and invalid-configuration body/metadata rollback pass.

Maximum CPU state-error gate ratio is3.3306691e-6; maximum normalized translation
ratio is0.005093694; maximum analytic-reference ratio is0.004984794. Minimum
observed absolute dynamic gap is0.006999999999995232m. Largest evaluated-relative
gap error versus exact stored-coordinate subtraction is4.1633363e-16m.

The frozen design's “18 integration steps” means outer observations. The existing
1/120s ceiling executes36 substeps per body over.3s. Pair position accumulation
therefore contributes at most36ulp, plus bounded input/subtraction error, within
the predeclared64ulp envelope. At|coordinate|<260, ulp≤2^-44; the conservative
64ulp+64eps*(1+4) bound is3.7090331e-12m, below the unchanged2^-36m margin
(1.4551915e-11m). This clarification changes no cases, gates or margin.

Commands: `python3 scripts/qualify-translation-boundary.py source --slot-confirmed`
and corresponding `packaged`; use an unexecuted range or a new evidence directory
rather than overwriting recorded outcomes. Existing range/build receipts retain
all fingerprints. Source/fresh-precompiled rank checks and the exact original
collision repros pass; source/precompiled lifecycle, sphere/box, box/box detection
and box response regressions pass with verified identical production dependencies.

Full receipt and checksums: `build/physics-translation-boundary/{verification.json,
COVERAGE.md,new-coverage.json,regressions.json,SHA256SUMS}`. The initial test-only
compile-field diagnostic is preserved in `compile-attempt-1`; no GPU fixture
failure was removed or reclassified.

The two baseline64 convergence rejects, four old one-second ledge scenes without
detachment, and strict original translation failure remain separate. Independent
ledge events remain12/12 source/precompiled and do not inflate original coverage.
The coupled solver stays expensive and opt-in. No general stack, performance,
real-time or broad PhysX-parity claim follows. H3 stays paused; SDK/campaign,
asset/save identities, original baselines, pins, dirty work and settings remain.
