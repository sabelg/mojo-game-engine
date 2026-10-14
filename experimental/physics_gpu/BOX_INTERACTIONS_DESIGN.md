# Predeclared bounded multi-step interacting-box correctness increment

This extends tests of the current GpuBoxResponse, not its solver, default policy,
shape support or admission profile. Freeze this document and the case matrix before
any trajectory execution. Existing BOX_RESPONSE_DESIGN.md, baseline64 fixtures,
explicit96 alternative, numerical gates and historical failures remain unchanged.
No warm start, history, parallelism, broadphase, sleep, render or performance work.

## Inputs and case matrix

SI binary64 cubes: half extents (.5,.5,.5), mass2 kg and isotropic cube inertia.
Fixed floor half extents (5,.25,5), center (0,-.25,0), except finite ledge (.5,.25,1).
Rest cube centers y=.5+(i-1)-i*1e-5. Coordinates remain within10 m. Gravity
(0,-9.81,0), except closed two-body collision with zero gravity. No forces/torques.
Initial translations <=.06 m, yaw/tilt <=.02 rad, initial linear components <=.5
m/s and angular components <=.1 rad/s; subsequent velocities stay in inherited
physical profile. Restitution0 except bounce and closed collision .5. Mu0,.2,.6.
Dt1/30,1/60, selected refinement1/120, no substeps, position64; compare requested
velocity64 under baseline64 with velocity96 under explicit96. Both numerical
policies are explicit, unchanged constructor values. Stop each case at first
rejection or check failure; a partial prefix is not a qualified full trajectory.

Cases run at30/60Hz under both policies (44 runs), seeds17,29,43,61 for case5
(additional12 runs). Cases2/3/6/8 also run at120Hz under both policies (8 runs).
Case0/6/8 at60Hz explicit96 each get translation(+2,0,+1) and x-reflection
variants (6 runs). Total70 independently initialized finite trajectories:

| id | Case | Definition | Duration |
|---|---|---|---|
|0|Offset rest|Two cubes, upper x=.06; mu0.|.5s|
|1|Yawed offset rest|Two cubes, yaw lower+.02/upper-.02; upper x=.03; mu0.|.5s|
|2|Tilt settling|One cube tilted+.02 aboutz, center at its exact rotated vertical half extent minus1e-5; mu0.|.5s|
|3|Shared frictional slide|Two cubes, each v=(.3,0,.05), upper x=.03; mu.2.|.5s|
|4|Spin and slide|One cube yaw.02, v=(.3,0,.1), omega=(0,.1,0); mu.6.|.5s|
|5|Seeded small perturbations|Two cubes; upper x=.02+.001*n(seed,0), z=.001*n(seed,1); yaw=.01+.002*n(seed,i+2); v=(1e-4*n(seed,i+4),0,1e-4*n(seed,i+6)); omega=(0,1e-4*n(seed,i+8),0); mu.2.|.5s|
|6|Contact creation/loss and bounce|One cube center y=.7, initially stationary over floor; restitution.5, mu0.|1s|
|7|Support removal|One supported cube; remove floor body before step hz//8, then attempt stale floor update (byte rollback required); detached cube free-falls; mu0.|.5s|
|8|Closed frictional collision|Two cubes at x=-.55,+.55,y=0; v=(+.5,+.04,0),(-.5,-.04,0); zero gravity, restitution.5, mu.2.|1s|
|9|Finite ledge exit|One cube on ledge at x=.3, v=(.5,0,0); mu0. Contact creation/loss and rotation observed.|1s|
|10|Three offset rest|Three cubes, x=0,+.03,-.03; mu0; preserved centered counterpart remains independent.|.5s|

Seed perturbation n(seed,k)=(((seed*(17*k+13)+29*k)%97)/48)-1, fixed integer
modulo97 sequence, not a statistical random claim. Reflection transforms polar
position/velocity x signs, axial angular y/z signs and quaternion y/z signs.
Translation/reflection are applied to all bodies, including the fixed floor.
Baseline counterpart and metamorphic runs use the same physical inputs thereafter.

## Numerical and physical gates (before results)

Inherited normal complementarity <=1e-9*(1+max initial normal speed), tangent
fixed-point <=1e-9*(1+max initial tangent speed), per-point cone <=1e-12*(1+mu*lambda),
kinetic velocity-stage gain <=1e-9*(1+Kbefore), post depth <=1e-5+1e-9m, correction
<=.25m. Read the actual per-call gates; validate each selected point cone directly.
Independent CPU corner/constructive geometry, scalar normal-block and spectral
Coulomb solve compare all23 active-body fields per successful step at
1e-10*(1+abs(expected)), plus energy/depth. No GPU solved state supplies expectations.
No conditional SAT feature convention is enabled initially; any ambiguity is
reported, not treated as a silently unique independent answer.

Integration linear momentum, gravity/free-flight analytic positions/velocities and
closed velocity-stage linear/angular momentum at projected poses use the original
1e-10*(1+abs(expected)) gate. Cube inertia is isotropic; angular momentum is
I*omega plus COM cross m*v. Artificial COM projection orbital change is recorded
separately, never mistaken for conserved position-stage angular momentum.
Gravity integration and total (K+U) accounting, cumulative projection work and
kinetic dissipation use1e-9*(1+abs(initial energy)+abs(work)+abs(dissipation)).
These scenes have isotropic inertia and constant gravity; free-flight energy is
analytically conserved by the existing integrator to that gate.

Rest cases0/1/5/10 retain max displacement<=1e-4m and orientation-basis change
<=1e-3 (radian-equivalent for these small changes), and final-quarter speed/angular
jitter<=1e-3. Moving/settling cases measure displacement and orientation but do
not require zero motion; independent state error and physical contact/energy gates
apply. No general stack or long-duration claim from .5/1s trajectories.
Complete case6 must create and lose contact, and match thresholded restitution
in an axis-aligned impact. Complete case8 must create and lose contact and preserve
closed velocity momentum. Complete case7 must lose support, reject the stale
update without state/registry change, and match analytic free fall from removal.
Complete case9 must lose contact; otherwise its requested exit is not covered.
No-contact frames must preserve response-entry body bytes. Fixed bodies and pending
force/torque fields are bit checked. Each failed response must retain the complete
raw authoritative body array and metadata at response entry; prior integration and
orphan reconciliation are separate commits.

Metamorphic all23 field comparisons retain1e-10*(1+abs(expected)); policy/error/
completion, contact counts and physical summaries are compared independently.
A mismatch at finite iteration/order is a retained limit, not gate relaxation.
Exact trajectory failures, CPU/GPU codes, first frame, stats, residual history,
raw entry/after rollback evidence and qualified prefixes must be recorded.

## Resource and stop boundary

Exclusive native/GPU slot, H3 paused, matching pinned Mojo/MAX, one build thread,
180s build/30s each trajectory, 32GiB available-memory reserve and normal settings.
No installations/system/power changes. Preserve all prior evidence and unrelated
work, campaign/assets/save identities and normal SDK. Source/precompiled paths
and applicable retained regressions run against final fingerprints. Stop at this
bounded correctness checkpoint; report a clear matrix and the next concrete blocker.
