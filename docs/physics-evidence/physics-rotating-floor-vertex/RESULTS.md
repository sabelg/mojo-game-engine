# Rotating single-vertex floor impact: bounded prerequisite passed

The isolated `rotating_floor_vertex_impact` primitive passed **5,144 source/fresh-package records**. Each path contains2,560 primary cases (1,536 accepted impacts,1,024 expected exact rollbacks) and12 actual-poststate continuing-contact calls. Full JSON outputs are byte-identical between source and the fresh minimal five-module package. All sixteen cyclic/reversed enumeration orders give identical canonical geometry, metric and physical results, and all eight possible lowest vertices are exercised. Stop reached: completed smallest prerequisite for review. No trajectory integration, TOI solver, multibody implementation or timing followed.

## Physical change and supported scope

The primitive refreshes all eight material vertices from the actual body quaternion, shape-local quaternion and shape-local center. It admits exactly one lowest vertex within the original1e-9m contact band, with all other vertices outside that band, against a fixed infinite horizontal floor. Its actual point velocity is `v + omega x r`; the full world inertia tensor and3x3 point-velocity metric retain normal/tangent and angular coupling. It applies only the analytic frictionless normal impulse, `lambda=(beta-u_n)/K_nn` for closing contact, and zero impulse for opening contact. Real torque `r x J` changes angular velocity through world inverse inertia. Mass, inertia, pose, force and torque are bit-preserved. No position correction or angular clamp is used.

This is a cold instantaneous impact map with **mu=0**, not an advance owner or frictional rotating support solver. Restitution uses the existing incoming point-speed threshold-.2m/s. A caller-authorized new impact freezes `beta=-e*u_n`; continuing contact uses beta0. The primitive cannot validate a world episode flag by itself. A future owner must validate body/shape generations, shape revisions, full material feature identity and actual separation history. The12 continuing calls/path use the actual accepted output state, produce zero new restitution target/consumption and no second bounce energy. Opening/zero-impulse cases preserve all state bits.

The qualified straight-sliding temporal owners, frozen block, all prior performance/qualification evidence, toolchains and unrelated work remain unchanged. The old flat-face pressure-redistribution shortcut is not used.

## Independent correctness

The independent Decimal80 oracle uses exact Float64 inputs, explicit quaternion-to-matrix geometry, a full world inertia matrix with independent Gaussian-Jordan inversion, and a cross-product matrix congruence for all nine point-metric entries. It derives the analytic single-contact impulse, poststate and loss `.5*(1-e_eff^2)*u_n^2/K_nn`. It imports no production Mojo/core equation helpers. Native tests compare every state component to the unchanged1e-10*(1+abs(reference)) gate and all reported geometry/metric/impulse diagnostics to the precomputed reference. Maximum state gate ratio:2.83747e-06; maximum diagnostic gate ratio:0.000585929, both below1.

A separate Decimal80 check applies the full inertia tensor to the **actual native poststate**, independently of the kernel's own diagnostic errors. It checks linear momentum change J, world angular momentum change r x J, angular momentum about a fixed origin change p x J, normal residual and analytic energy loss. Maximum measured discrepancies:

| Independent invariant | Maximum error |
|---|---:|
| Linear momentum | 3.10862e-15 kg m/s |
| World angular momentum | 1.96302e-14 kg m²/s |
| Fixed-origin angular momentum | 1.96302e-14 kg m²/s |
| Normal residual | 4.48585e-16 m/s |
| Energy balance | 7.43052e-15 J |

Four mass/inertia/aspect variants cover arbitrary pitch/roll/yaw, inverted contact on vertices outside the old local bottom face, shape-local rotations/offsets, translated floor/body positions, e0/.5/1, exact restitution threshold and nearby cases, signed near-zero/zero/opening velocity, continuing compressed contact, and unchanged external force/torque fields. All original normal/energy/profile gates and exact input/canary checks remain unchanged.

Angular-only closing cases have COM normal velocity0 but an approaching material vertex. They receive a physical impulse and retain substantial real post-impact rotation (all tested post-omega norms>.1rad/s). For the anisotropic variant m=.1kg, I=(.01,.02,.025)kgm², the yaw case starts omega=(0,1,0)rad/s and ends approximately(1.153454,1.123624,-.533272)rad/s. The changed yaw velocity is physically required by world inertia coupling; world angular momentum along the normal remains unchanged. The block never forces yaw or tipping to zero. `independent-invariant-proof.json` records actual angular-velocity/world-momentum examples.

## Rejected states and atomicity

Expected rejected domains: edge/face ties and near-degenerate contacts, nonzero friction, invalid restitution/episode/enumeration, malformed shape geometry or quaternion, unsupported initial profile, separated/penetrated snapshots and post-impulse angular profile overflow. The last is physically possible motion outside the existing bounded profile; it is rejected, not clamped or suppressed. Every rejection preserves all38 public state/descriptor words bit for bit and consumes no episode designation. Every call preserves the complete96-word input and output canaries0/95. No world identity/registry transaction is claimed by this standalone raw block.

No trajectory claim is made. Moving geometry needs the earliest all-vertex root along actual angular evolution; the COM quadratic floor root is insufficient. Before a rotating trajectory owner, the next stage must independently qualify torque-free/forced Euler/quaternion evolution with high-accuracy reference/refinement, normal-gap derivative coupling, grazing roots, feature transitions, nonpenetration, complete time consumption and episode rollback. Edge/face coupled contact, circular maximum-dissipation friction, finite-floor admission and interacting bodies remain future work. Accuracy relaxation requires user approval; none was requested or applied.

## Resources, recovery and preservation

Two harness buffers,96Float64 words each /1,536explicit bytes total. No existing owner buffers changed. Builds used one thread; fresh-package precompile used one CPU. Guards were finite180s build/30s native, one execution/GPU slot, with>=32GiB available memory. Minimum sampled available memory:111.523GiB; final:113.739GiB.

All19,623protected hashes,5,901asset/save size/mtime identities,17campaign source hashes and119unrelated source/lock hashes match. Mojo1.2.0.dev2026092905 / isolatedMAX26.7.0.dev2026092905 metadata hashes match. H3 remains paused and untouched; hardware/driver/power/security/profiling settings were unchanged; no installs or counter retries. Dynamic spills/stalls remain unmeasured.

The first harness compile's String length API error was corrected to byte_length before native execution. A transient execution-server disconnection prevented the first correction attempt and corrected compile from starting. Recovery checked actual files and owned processes, proved that attempt had no log/telemetry and no owned job, saved the correction, then ran only missing stages. Failed compile and transport/recovery receipts are retained. No physics gates or fixture values were changed after native execution began.

Final audit: no owned jobs and no GPU compute processes remain. Evidence: `DESIGN.md`, `verification.json`, independent references/invariant proof, exact source/package JSONL records, fingerprints, compile/native telemetry, transport/recovery receipt, preservation/idle audit and `FINAL-SHA256SUMS`.
