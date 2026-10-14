# Predeclared translated-boundary numerical contract and fixtures

The original same-time translation test remains a failed strict test. Preserve
its exact original/translated encoded inputs, binary64 bits, response/event traces
and prior63/70 coverage. No contact epsilon/slop, physical gate, timestep, iteration
budget, integrator, stored-coordinate representation or production feature change
is proposed. This is a separate bounded diagnosis and robust-domain test increment.

## Existing strict behavior and unsupported near-boundary promise

Box SAT already uses pair-relative center differences. Its current evaluated
binary64 signed gap remains strict: positive separates, nonpositive contacts.
This does not imply exact real-arithmetic translation invariance for arbitrary
independently rounded stored coordinates or repeated absolute-position updates.
At a sign-changing near-zero gap, an arbitrarily small geometry change can change
discrete impact time and produce a large same-time response difference. A physical
state gate cannot legitimately be widened to equate those different event sequences.

In the original repro, translated initial separation is2.220446049250313e-16
smaller in exact dyadic arithmetic. At frame5 (nominal0.1s), stored face gaps are
+4.440892098500626e-16 original and-2.442490654175344e-15 translated. Pair-relative
SAT evaluates each gap exactly. Exact integration of the stored initial inputs
and displacement also leaves opposite signs (+9.02056e-17/-1.31839e-16), so more
precise SAT or arithmetic does not erase the encoded-input distinction. Exact
same-time event invariance there remains unsupported; each individual stored-input
trajectory is still checked against independent CPU/physical/rollback gates.

## Supported separate test domain

Axis-aligned, unforced cubic bodies, two identical mass2 bodies, zero gravity,
zero initial spin and transverse velocity; half extents h=.125,.5,2; prescribed
isotropic inertia from the existing half*2 factory. Common translations
(T,T/2,-T/4), T=0,+2,-2,+256,-256. All coordinates remain within the inherited
response profile, all shape sizes within.05..10. No scale or coordinate expansion.
Rebound coefficient.5, unchanged one-coefficient circular Coulomb law mu.2,
explicit96 outer sweeps and64 position sweeps. Existing component/state1e-10,
energy/work1e-9, cone1e-12, depth1e-5+1e-9, profile and byte-rollback gates remain.

The tested resolved gap domain has margin larger than2^-36m (about1.46e-11) before
impact. This is an eligibility/error-envelope statement, never an input to SAT or
a contact epsilon. Before impact, all directions are identity Cartesian axes.
For |coordinate|<260, per-center ulp is<=2^-44; <=18 integration steps produce
at most18ulp in relative accumulation plus bounded input/subtraction/face-radius
rounding. Even a conservative64ulp plus64eps*(1+4) is below2^-36. Static resolved
gaps h*2^-16 are at least1.907e-6m. Dynamic preactivation/activation gaps are at
least.007m/.0096m from zero. Thus declared signs are resolvable at every translation.
Exact touching is separately tested only for dyadic centers T±h, radii h and
Cartesian axes whose evaluated relative gap is provably exactly0; this is not a
promise for arbitrary near-zero encodings/orientations.

75 separately initialized fixtures per path:

- Static45: three h values times five translations times gap sign positive,
  exact0, negative. Centers T±(h+gap/2) inx, common y=T/2,z=-T/4. Both initial
  velocities(+.5,0,0),(-.5,0,0). Detection sign and gap match independent analytic
  intervals/CPU corner geometry. Positive gap has no impulse/body-byte change;
  touching/overlap has one four-point patch and the centered closed-form rebound
  velocities(-.25,0,0),(+.25,0,0), zero spin, total normal impulse1.5, kinetic
  energy.5→.125 and conserved closed momentum/angular momentum. Projection work
  is separate. Invalid resolve configuration must retain exact body/metadata bytes.
- Dynamic30: three h values times five translations times30/60Hz, duration.3s.
  Initial gap.107 and velocities±.5 give nominal crossingt.107s, deliberately off
  both grids. Before crossing exact interval signs are separated. First impact is
  at4/30s or7/60s; previous observations are.1s. Position projection to original
  slop and velocity-stage rebound obey the same centered closed form. Subsequent
  outward motion cannot recontact; compare all23 states with independent CPU and
  after subtracting the common translation with the baselineT0 at the original
  state gate. Check no false/missed impact, one creation/end, contact-free bytes,
  analytic rebound/free flight, energy/work and fixed accumulator identity.

Reported event times are discrete observed times with brackets, not exact continuum
collision timestamps or CCD qualification. Source/precompiled canonical records
must agree. Keep exact original failed strict test distinct from robust fixtures;
never inflate the old70-case pass count with this new set. No production correction
is justified by the localized repro. Preserve any newly failing fixture; no gate or
eligibility margin tuning after execution to make a failure pass.

Resource policy: exclusive native/GPU slot, H3paused; matched locked Mojo/MAX,
one-thread compilation180s, each fixture30s,32GiB available reserve and normal
settings. No installs, OS/driver/power changes, performance work or new features.
Run fresh source/precompiled checks, exact saved repro and affected detection/
response/rollback regressions against final fingerprints; preserve SDK/campaign/
assets/saves/dirty work. Stop at this contract/coverage checkpoint and report
remaining baseline64 convergence and old strict-boundary limits separately.
