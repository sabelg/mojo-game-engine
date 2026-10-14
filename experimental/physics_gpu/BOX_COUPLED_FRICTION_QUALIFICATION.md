# Bounded opt-in coupled-friction qualification recovery

The original `GpuBoxResponse`, its numerical gates, prescribed inputs and historical
rejection remain unchanged. `GpuCoupledBoxResponse` is a separate experimental
policy. See [the frozen numerical design](BOX_COUPLED_FRICTION_DESIGN.md).

Recovery inspected saved artifacts and host jobs without reading private session
transcripts. The native CPU replay had already compiled after the partial checkpoint.
Its full shared-slide 30 Hz/96 trajectory exposed an independent geometry mismatch
at frame 3. Both solvers returned success; the reference footprint had lost corners.
The failing trace and the later diagnostic compile error are retained under
`build/physics-box-friction/runs/source-interactions/` and
`build/physics-box-friction/reference-geometry-probe-compile.log`.

The correction is restricted to the coupled CPU oracle. Its own
`coupled_geometry_reference.mojo` uses constructive gift wrapping with farthest
collinear endpoints, replacing the exact-abscissa monotone hull ordering that lost
rectangle corners under binary64 orientation noise. It uses the existing polygon
resolution. SAT separation, solver laws and every physical/state gate are unchanged;
the original geometry/reference files retain their baseline fingerprints. The two
saved inputs now both produce four independent footprint corners. Diagnostic
attempts, including the unsuccessful ordering-only attempt, are retained.

Final source/precompiled coverage, physical checks, work counters, host/API wall
cost and remaining limits are recorded in:

- `build/physics-box-friction/recovered/final/COVERAGE.md`
- `build/physics-box-friction/recovered/final/coverage-matrix.json`
- `build/physics-box-friction/recovered/final/verification.json`

All 70 source and 70 freshly precompiled cases executed within their original
30-second run guards. Records and trace arithmetic match exactly across paths.
Each path qualifies 62 full trajectories; 63 pass local trajectory checks, with
the translated collision excluded by its failed metamorphic gate. The remaining
cases comprise two retained frictionless64 solver rejections, four unreached
ledge events and one seed-61 independent state mismatch.

The analytic shared-slide target passes at tangent bases0/45/90 with independent
CPU replay, closed-form velocity/pressure/energy, and original residual/cone gates.
At basis0 it takes96 explicit outer sweeps,437 Newton corrections and2066 residual
evaluations. Final synchronized host/API wall cost is1.02–1.16 seconds across both
paths; this is not GPU-only timing or evidence of an efficient replacement.

A local completed trajectory does not establish general stack stability. The
original strict same-time translated collision boundary failure and four finite
ledge scenes that never detached remain separate limits. A seed-61 perturbation at
30 Hz/64 sweeps also fails the independent state gate at frame 7 and is retained,
without a gate or input adjustment. The matching 96-sweep fixture is separate.
No performance, general PhysX parity, production adoption or publication follows
from this bounded qualification.
