# Predeclared separate bounded ledge-event fixtures

The original70-case matrix, its four one-second ledge records and all gates stay
unchanged. Those trajectories completed numerical checks while contact persisted;
they remain inconclusive for detachment. The new tests are a separate event set,
not additional passes in the original70-case denominator. No production change,
friction change, performance work or new physics feature is proposed.

Use the opt-in GpuCoupledBoxResponse and independent CpuCoupledBoxResponse, existing
finite box/box detector and generation-safe body/shape APIs. SI binary64 cube
half extents(.5,.5,.5), mass2, prescribed diagonal inertia4/3; fixed ledge half
extents(.5,.25,1), center(0,-.25,0). Both policies64/96 at30/60Hz; position64,
restitution0, original ledge coefficient0 throughout. No substeps, forces/torques,
impulse reuse, warm start, history integration or scheduling changes. Twelve
separate finite runs: three mechanisms times two rates times two explicit policies.

## Mechanisms and analytic guarantees

0. Controlled support removal/reuse. Cube center(0,.49999,0), initially stationary,
gravity(0,-9.81,0), duration.6s. Before the step starting at.2s, remove the support
body. Immediately detect and observe ending of its old generation-safe pair at
command time.2s. Reject a stale body update and old shape detach with exact
body/metadata/registry rollback. Recreate a fixed ledge atx=-3 in the recycled
body/shape slots: generation must advance, namespace must remain valid, and the
old pair may never become persistent again. This replacement cannot overlap the
cube. The original cube must preserve its identity, remain contact-free, and
match p=p_remove+v_remove*t+.5*g*t², v=v_remove+g*t after removal. Explicit support
removal is distinct from physical lateral runoff.

1. Analytic horizontal geometric exit followed by gravity. Cube center(.29,.49999,0),
v=(2,0,0), omega0, gravity0 until the first contact-free observation; gravity9.81
downward from the following step onward. Duration.7s. With zero incoming normal
speed and penetration no deeper than existing slop, normal impulses and torque
are zero, orientation stays identity, and x=.29+2*t. Strict horizontal separation
occurs for x-0.5>0.5, so t_cross=.355s. This is deliberately off both timestep
grids: first discrete ending is step11/30 or22/60, t=11/30s. Geometric contact
before then and absence after then are independent scalar interval checks. Gravity
activation is an explicit test command, not natural gravity-driven departure;
its potential-energy change is recorded as external field work. After activation,
check analytic free fall from the ending snapshot, constant horizontal velocity,
zero spin and continued horizontal separation. This covers a closed-form contact
ending rather than a weight-supported tipping law.

2. Gravity-driven frictionless runoff. Cube center(.29,.49999,0), v=(4,0,0), omega0,
gravity(0,-9.81,0), duration.6s. Material coefficient remains the original0.
For this rightward planar runoff, verify before ending that every independent
and GPU contact normal has nonnegative x component (representation gate1e-12),
normal impulses are nonnegative, vx never drops below4, and COM projection never
moves left. Verify the modest clockwise planar orientation branch before ending.
These are explicit analytic branch conditions, not silently assumed passes.
They imply x>=.29+4*t. Any cube orientation has horizontal half extent<=sqrt(3)/2,
so at t=.3s its entire bounding sphere is right of the ledge by at least
.29+4*.3-.5-sqrt(3)/2 >.12m. Hence contact loss must occur by.3s if those checked
branch conditions hold. Record the first actual discrete event and its bracket;
do not claim an exact continuum event time. Thereafter check analytic constant-
gravity COM free fall, constant linear horizontal/angular velocity, independent
contact absence and energy/work. No friction is lowered to manufacture departure.

All cases start with contact. Initial/new, persistent and ended transitions are
explicit test-derived diagnostics from generation-safe BoxContactPatch.PairKey
snapshots, not new production history events. Validate body/shape owner namespace,
slot, generation and revision per present pair; preserve the old key on ending.
Body/shape reuse must not alias the old support. Detection epochs increase; when
contact is absent, response-entry body bytes are unchanged. Event continuity is
checked against independent CPU geometry and scalar analytic gap/clearance tests.

## Unchanged correctness gates and transaction scopes

Independent CPU replay of all23 body fields:1e-10*(1+abs(reference)); original
normal/tangent residuals, per-point Coulomb admissibility, kinetic gain, profile,
maximum depth1e-5+1e-9, maximum projection.25, and fixed/force/torque byte gates.
Gravity integration momentum and energy use inherited gates. Total K+U accounts
separately for COM projection work, kinetic dissipation, and prescribed gravity-
field changes. Rotation during free flight uses independent CPU replay and
constant isotropic angular velocity; no exact contact-time claim at a binary64
strict boundary. Support deletion/orphan reconciliation are existing separate
commits and not rolled back with later response publication.

Predeclare before trajectory execution; preserve any failing new fixture. Source
and freshly precompiled actual GPU paths use final fingerprints. Exclusive slot,
H3 paused, one-thread compilation180s and each run30s,32GiB available reserve,
normal settings and matched Mojo/MAX pins. Preserve baselines/SDK/campaign/assets/
saves/dirty work. Stop after this bounded event increment. The two baseline64
convergence rejections and translated strict-boundary failure remain separate.
