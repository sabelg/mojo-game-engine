# Bounded multi-step interacting-box correctness checkpoint

The existing separate `GpuBoxResponse` solver and64/explicit96 policies are
unchanged. This checkpoint adds a frozen70-case trajectory matrix and independent
source/precompiled checks; it does not add warm starting, shapes, parallelism,
broadphase, sleeping, campaign integration or performance qualification.

Reproduce from the Atlas root with the exclusive native/GPU slot and H3 paused:

```
python3 scripts/prepare-box-interactions.py
python3 scripts/qualify-box-interactions.py source --slot-confirmed
python3 scripts/qualify-box-interactions.py packaged --slot-confirmed
```

The preparation command preserves existing declarations/evidence; it never
rewrites an existing frozen matrix. The native executable takes output prefix,
scene id, Hz, policy, seed and transform variant. Each finite case writes an
initial-state record, per-step trace and explicit result. Convergence rejection
is recorded as rejection, not as a successful trajectory or a failed harness.

[Predeclared design](BOX_INTERACTIONS_DESIGN.md) and
[case matrix](BOX_INTERACTIONS_CASES.json) specify inputs, numerical/physical gates,
durations and resource limits before execution. Independent CPU geometry and
scalar/spectral response replay never supplies GPU body state. All23 fields,
report energies/depth, residual gates, per-point cones, gravity integration,
energy/projection-work accounting, fixed/accumulator bytes and full response
rollback are checked. Closed collisions additionally check linear/angular
momentum at projected poses. No-contact frames preserve all body bytes. Support
removal includes stale-update registry/body rollback and analytic free fall.

## Results and exact qualified domain

Each source and precompiled matrix has50 locally complete trajectories,16
matching CPU/GPU convergence rejections and4 incomplete event-coverage outcomes.
Every result and trace is bit-for-bit identical between the two builds.
One locally complete translated collision fails its metamorphic comparison;
49 cases per build pass every applicable designated gate. Ten of12 metamorphic
comparisons across both builds pass. Counts refer to discrete fixtures, not a
continuous parameter-range or general-stack guarantee.

Qualified with unchanged physical gates:

- Two-cube .06m offset rest and .03m offset/opposing .02rad yaw rest: .5s at30/60Hz,
  both64/96 policies. Translation/reflection of the offset-rest60Hz/96 fixture pass.
- One-cube .02rad tilt settling: .5s at30/60/120Hz, both policies.
- One-cube spin/slide, yaw.02, v(.3,0,.1), omega_y.1, mu.6: .5s at30/60Hz,
  both policies. This is not shared frictional-stack qualification.
- All four declared seeded small yaw/offset/velocity perturbations: two cubes,
  mu.2, .5s at30/60Hz under explicit96, up to70 sweeps. Baseline64 rejects every
  first step; no baseline-policy success is implied.
- Axis-aligned .5-restitution bounce:1s at30/60/120Hz, both policies; contact
  creation/loss and analytic free flight/restitution pass. Translation/reflection
  at60Hz/96 pass.
- Support removal: .5s at30/60Hz, both policies; stale update rollback, contact
  loss and subsequent analytic free fall pass.
- Closed two-box mu.2/restitution.5 collision:1s at30/60/120Hz, both policies;
  contact creation/loss and closed velocity momentum/energy checks pass locally.
  Reflection60Hz/96 passes. Translation60Hz/96 is explicitly not qualified.
- Three-cube offsets0,+.03,-.03: .5s at30/60Hz under explicit96, up to67 sweeps.
  Baseline64 rejects at frame0, including60Hz; preserved centered60Hz behavior
  remains separately qualified and unchanged.

## Retained failures and next blockers

Shared two-cube slide, upper offset.03, v(.3,0,.05), mu.2, rejects at frame0 with
114 under both policies at30/60/120Hz. GPU and independent CPU agree and full
response-entry body/metadata rollback passes. At30Hz, normal/tangent residuals
at64 are6.5131267e-7/1.2747658e-5; at96,3.6943899e-7/8.5330273e-6, versus unchanged
normal1.327e-9/tangent1.3041381e-9 gates. The tangent residual is still6543 gate
units at96 (3289 at60Hz;1649 at120Hz). First64 normal-history entries are identical
under64/96. The observed64-to96 geometric-mean tangent contraction is about.9875
per sweep; this is a local measurement, not an asymptotic rate or convergence
prediction. Fixed-budget coupled-friction convergence is the next stability
blocker. No larger policy or algorithm is introduced to hide it.

The closed-collision translation by(+2,0,+1) fails same-time state/count
invariance at frame5 (t=.1s): the exact binary64 face gap is+4.4408920985e-16 in
the original and-2.4424906542e-15 after translated position integration. The strict
signed-boundary law delays the original impact to frame6 but resolves the
translated impact at frame5, changing subsequent restitution timing/state.
Independent CPU and GPU reproduce each configuration. This is retained floating-
point boundary sensitivity; no contact epsilon, feature tolerance or state gate
was changed. Future boundary robustness needs its own representation/contract
choice and unchanged strict-boundary regression protection.

All four finite-ledge1s runs pass local numerical/replay gates but remain
contacting. The intended departure event is not reached or qualified; actual
rotated extent still overlaps the ledge. This is a fixture event-coverage gap,
not evidence of a bad solver or a completed ledge departure. Creation/loss is
independently covered by bounce, closed collision and support removal.

Project evidence: `build/physics-box-interactions/verification.json`,
`COVERAGE.md`, `coverage-matrix.json`, `failures.json`, `physical-metrics.json`,
`convergence-diagnosis.json`, `boundary-translation-diagnosis.json` and full traces.
Existing centered two-second fixtures,64 failure/explicit96 alternative, source/
precompiled numerical gates, original sphere paths, SDK, campaign, assets, pins
and settings remain preserved. This checkpoint stops before any solver change.
