# G05b bounded island-aware sleep/wake design

This increment adds generation-safe GPU sleep state to a separate opt-in owner
using the qualified stable response. The recommended API stays unchanged.
Correctness precedes throughput. Connectivity remains the G05a serial GPU method.

The qualified policy is deliberately conservative:

- All dynamic members of an island sleep together after a configured dwell time
  of continuously stable poses within an eight-machine-epsilon, scale-aware
  Float64 representation envelope over the entire dwell interval, exactly zero representable linear/angular
  motion, and exactly zero pending external force/torque. Testing components
  directly avoids squared-norm underflow hiding tiny physical motion. The pose envelope is 8*Float64.epsilon*max(1,abs(anchor),abs(current)) per
  pose coordinate, with a fixed anchor across dwell; it never hides nonzero
  velocity, force, angular motion or explicit edit intent. Numerical
  residual motion can prevent sleep; no approximate motion threshold is claimed.
- Zero gravity permits stationary isolated bodies. Under nonzero gravity, every
  member needs a current shallow contact-support path to a fixed anchor with
  reaction normals parallel to anti-gravity (dot >= 1-1e-12). This vertical-support
  subset deliberately excludes friction-supported inclines and uncertain support.
  Qualified physics completion and bounded post-step pose stability provide the dwell
  evidence; free fall, rolling, rotation and deep/transient overlap cannot sleep.
- Dwell uses compensated Float64 elapsed seconds, not frame counts. Any invalid
  dt/configuration is rejected. Sleep/wake/epoch counters cannot wrap. Changes
  reset dwell rather than counting the edit timestep toward sleep.
- Explicit wake packets validate complete handle batches on GPU and wake whole
  affected dynamic islands. Body/shape commands, any representable motion or
  force, gravity changes, contact changes, removal/reuse, merges and splits wake
  both surviving old component members and their new dynamic components. Fixed
  bodies never bridge wake propagation. Moving/changed fixed obstacles wake their
  incident old/new dynamic partners, independently across unrelated groups.
- Supported mutation entrypoints record explicit command intent on GPU, including
  numerically identical updates. Direct edits through nested/private owners are
  outside the supported command boundary; meaningful numeric changes are also
  detected from resident snapshots. Fixed-only explicit wake handles are no-ops.

Actual work skipping is a separate **whole-world idle gate**, disabled by default.
It skips both integration and response only when GPU preflight confirms every
live dynamic body is already asleep, supported and unchanged, with no wake source
or pending force. Empty/fixed-only worlds do not use the gate. When any island is
awake, the unchanged qualified integration/response executes for all bodies.
There is no per-island integration or solver skip, no omitted gravity on a sleeper
hit by an incoming awake body, and no new scheduling/geometry/warm starting.
Unrelated islands keep their sleep classifications when their full-step poses
remain exactly unchanged. Any pose change of a previously sleeping member wakes
its whole island on the full path, even if it is within the dwell envelope.
Skipped integration/response API operations are explicitly
counted from executed control flow; no speedup or kernel/throughput claim follows.

Sleeping with the gate enabled is exact pose preservation. With the gate disabled
or an awake island present, actual response remains qualified; a body whose pose
or motion changes is awake at the next completed publication. Sleep observations
refer to a completed sleep epoch, not to an in-flight or failed physics step.

Sleep metadata and wake-request consumption publish only after successful physics
and validation. Failed integration/response does not advance dwell or sleep epoch
and retains requests. Existing integration, response, lifecycle and orphan pruning
remain separate commits; an error after integration may leave that earlier body
commit visible. This scope is explicit rather than a new whole-step rollback API.
Snapshot state after failure describes the earlier completed sleep epoch; retry
preflight reads actual current bodies and retained requests before any idle skip.

Qualification covers source/precompiled actual GPU state-machine and analytic
sequences, dwell rates/boundaries, free fall/low motion, force/impulse wake, support
and obstacle edits, merge/split/reuse, stale batches, rollback, actual idle skipping
and unchanged active-path stable response. A short diagnostic records the executed calls and events.
One-thread 180s compile/30s run limits, exclusive slot, 32 GiB reserve, unchanged
pins/settings and paused H3 remain mandatory. Stop at G05b before broader sleep
eligibility, per-island skipping or scheduling. No community code/dependency reuse.

## Qualified API and execution boundary

```mojo
from experimental.physics_gpu.sleep import GpuSleepingPhysics
var world=GpuSleepingPhysics(sleep_after=.5, idle_gate=True)
# world.submit(BodyCommand batches), submit_shapes and submit_boxes are the
# supported mutation entrypoints; wake validates a whole BodyHandle packet.
var result=world.step(1.0/60, coefficient=.8)
# result.integration_calls/response_calls are actual invoked API operations.
var members=world.snapshot()  # explicit diagnostic readback of completed state
world.close()
```

The constructor's idle gate is **False by default**. Sleep classification does
not imply skipped integration or response. The two counts are 0 or 1 per step,
not body-substep counts, individual kernel counts, throughput or DMA measurements.
Detection, GPU island construction and sleep/wake validation still execute on an
idle tick. Work-buffer canaries prove that the omitted integration/response calls
are not silently run. There is no per-island skip; partial-sleep scenes run the
entire qualified physics path, and any resulting pose change wakes that member's
island at completed publication. This conservative behavior can cause extra wakes
from representation noise; it does not couple dynamic groups through fixed roots.

Dwell anchors stay fixed through the entire eligible interval. The representation
envelope was selected after a preserved diagnostic found the existing solver's
one-ULP floor-position cycle with exactly zero velocity. It changes sleep eligibility
only; no geometry, solver tolerance or original numerical gate was altered.
Explicit command intent and preflight numeric changes always reset eligibility,
including identical body updates and shape-revision changes. Approximate-motion
sleep and general incline/pile sleep are not qualified; nonzero residual linear or
angular motion can keep an otherwise resting island awake indefinitely.

Supported-rest gravity fixtures passed at 30/60/120 Hz on shallow horizontal
sphere/fixed-box contacts. The support test is reachability through near-vertical
reaction normals, not a general equilibrium, support-polygon or loaded-friction
proof; general inclines, unstable piles and approximate residual-motion sleep
remain unqualified.

The supported domain inherits G04's Float64 correctness profile, 256 body slots,
64 shapes and at most 64 response contacts; G05a's larger graph-only contact
capacity is not a 2,016-contact solver claim. Step rates are 30–240 Hz (dt in
[1/240,1/30]), dwell is in [0,10] seconds, and existing restitution/friction,
iteration, body/shape and integration-substep limits stay enforced. Material,
iteration or gravity changes reset all dynamic dwell; dt changes accumulate true
elapsed time. Sleep/wake counts refer to live body transitions; removed/reused
identities retire their former state without aliasing a new body's dwell.

GPU state includes exact generation/namespace/roots, compensated per-body clocks,
fixed dwell anchors, previous body/shape/contact observations, pending requests,
private candidates and UInt64 epoch/event counters. Wake packets reject stale,
foreign/range or mixed invalid input without partially recording intent. Sleep
state/request consumption commits after successful qualified physics and counter
validation. Counter or response failure preserves previous sleep words/clocks and
requests; tests show the earlier integration commit can remain visible. Retry
checks actual current bodies and retained intent before considering idle work.
The single-caller synchronous owner is separate from the unchanged recommended
API; direct nested/private mutations are not the supported command contract.

## Coverage and evidence

Actual GPU source and distinct precompiled-package suites cover zero/maximum dwell,
rational 30/60/120/240-Hz and mixed-timestep expectations, a separate CPU BFS/rational
state machine, gravity-supported rest, exact idle frozen body words, static-only
wake no-op and no shared-static bridge, unsupported analytic free fall, extremely
small nonzero linear/angular motion and force intent, impulse/pose edits, incoming
contact wake, merges/splits, shape revision/detach, removal/reuse, stale mixed wake
packets, invalid configuration/corrupt clocks, exact MAX-1/MAX epochs, event-counter
exhaustion, retained-request retry, response rejection scope, gate-off/empty/256-body
capacity and actual work-buffer skip canaries. The active rolling path matches every
body value of the unchanged stable GPU response; existing independent CPU physics
oracles and original baselines are retained in final regressions.

Run `python3 scripts/qualify-sleep.py MODE --slot-confirmed`, with MODE `test`,
`packaged` or `demo`. The short device diagnostic freezes two supported islands,
applies force to one and removes their fixed support; it prints actual calls and
wake events. Evidence is `build/physics-g05-sleep/verification.json` and its
source/precompiled/diagnostic receipts and logs. Stop before broader sleep policies,
per-island work skipping or solver scheduling. No speedup is claimed.

The counted nine-step device diagnostic executed six integration calls and six
response calls and skipped both operations on three whole-world idle steps.
When force woke one island while the other remained asleep, both physics calls
executed; support removal also executed both calls before the next publication.
The isolated package adapter renames copied G04 helper entrypoints only; original
regression sources are unchanged.
