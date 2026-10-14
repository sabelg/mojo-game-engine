# Qualified unilateral temporal friction: bounded timing result

The qualified physics owner and all prior receipts are unchanged. Complete API latency was measured separately from traced GPU kernel sums. Source and a fresh exact-source package agree numerically; every accepted timed output matches its clock-disabled preflight output exactly after removing latency and sample index. No optimization or default promotion was made.

## Candidate API latency

Each cell is median [minimum–maximum] milliseconds over 24 warmed samples: three balanced sequential blocks of ten calls, excluding the first two calls of each process. The four fixtures share m=2 kg, I=(4/3,4/3,4/3) kg m², half=(.5,.5,.5) m, mu=.2, e=0, gravity=(0,-9.81,0), and duration1/30s. Starting body state is verified bit for bit before each call. Setup/reset is outside the timed interval; all force submission, advance, reconciliation, commit, synchronization and scalar status readbacks are inside. Additional diagnostics are outside. These reset calls measure identical-entry cost; the previously qualified genuine consecutive trajectories are reused for physical correctness.

| Fixture | Source API ms | Fresh-package API ms |
|---|---:|---:|
| steady axial sliding | 12.833 [12.080–13.805] | 13.317 [12.093–13.941] |
| within-frame stop | 8.268 [7.830–9.726] | 8.691 [7.833–10.095] |
| static holding with downward force | 6.003 [5.893–7.620] | 6.003 [5.897–8.021] |
| oblique inelastic impact | 13.489 [11.899–13.876] | 12.664 [11.908–13.619] |

Steady sliding starts at .3 m/s axially. Within-frame stopping starts at .0327 m/s, stopping after1/60s; no state is clamped. Static holding has zero tangential motion and a constant4N downward force. The oblique inelastic impact starts .002m above the floor at v=(.3,-1,.4)m/s and uses physical TOI then supported sliding. All four candidate physical and method-equation gates pass.

## Traced GPU kernel sums

CUDA/NVTX tracing through Nsight Systems, with CPU sampling, context switches, CUDA event tracing and memory-usage tracing disabled. Each cell is median [minimum–maximum] milliseconds over four warmed traced samples (six calls, first two excluded). Kernel launches are attributed by CUDA runtime correlation IDs inside the complete API NVTX range; reset kernels outside the range are excluded. These are separate runs from plain API latency. Do not subtract or add their medians to infer overhead.

| Fixture | Source GPU kernel sum ms | Fresh-package GPU kernel sum ms |
|---|---:|---:|
| steady axial sliding | 13.019 [12.005–13.754] | 12.487 [11.906–14.196] |
| within-frame stop | 7.809 [7.738–9.518] | 8.339 [7.739–9.244] |
| static holding with downward force | 5.845 [5.803–6.927] | 5.802 [5.802–5.900] |
| oblique inelastic impact | 12.963 [11.804–13.196] | 12.021 [11.806–13.460] |

`performance.json` includes complete distributions (quartiles, cold first calls and block medians), CUDA activity spans, copies/bytes, launches, synchronization durations and individual kernel sums. Synchronization durations overlap GPU execution; they are not additive overhead.

## Valid paired reference comparison and regressions

Only static holding meets the unchanged independent state gates for all three methods. Strict references use `GpuBoxResponse(velocity_budget=96)` with96 velocity iterations and64 position iterations, following a1/30s integration or four1/120s integrations, each with its own complete strict response. The strict endpoints retain the original1e-5m penetration slop; the candidate finishes at analytic zero gap. Each satisfies its own unchanged1e-10 scaled state equation and the original physical1e-5m+1e-9 bound; this is not exact inter-method state identity.

| Path/method | API ms median [range], n=24 | GPU kernel sum ms median [range], n=4 |
|---|---:|---:|
| source / candidate | 6.003 [5.893–7.620] | 5.845 [5.803–6.927] |
| source / strict macro | 4.706 [4.570–6.362] | 4.437 [4.146–4.459] |
| source / four strict substeps | 19.000 [16.967–20.932] | 18.085 [16.423–19.125] |
| package / candidate | 6.003 [5.897–8.021] | 5.802 [5.802–5.900] |
| package / strict macro | 4.701 [4.570–6.431] | 4.812 [4.445–5.082] |
| package / four strict substeps | 18.860 [16.845–20.907] | 17.119 [16.794–17.665] |

Matched warmed sample pairs within the same balanced block give candidate API changes of **+28.38% source / +28.94% package versus strict macro**, a regression; and **−66.43% source / −66.32% package versus four strict substeps**, a gain. All three block medians have the same direction for both paths/comparisons. Ratios of pooled medians differ slightly: +27.58%/+27.70% and−68.40%/−68.17%. No significance or hard tail guarantee follows from this bounded sample.

## Excluded reference cases and integration mismatch

The six strict sliding, stopping and oblique-impact reference pairs are not timed or accepted as performance comparisons. Three clock-disabled samples per pair/path are retained, with exact source/package outputs. Steady/stop/impact strict outputs return success except four strict substeps at the within-frame stop, which rejects with code114 (velocity convergence). Successful endpoint references still fail the unchanged1e-10 state/spin checks: steady macro velocity error1.104e-9m/s and spin1.838e-9rad/s; steady four-substep spin2.891e-10rad/s; stop macro spin7.684e-10rad/s; impact macro/four-step velocity error4.222e-10/4.361e-10m/s and spin7.087e-10/1.026e-9rad/s. Gates were not relaxed.

Even independently of that rejection, the integration equations differ. Existing strict `BodyState.integrate` advances at the pre-contact velocity (midpoint external-force integration), then resolves contact at the interval endpoint. Candidate cold groups change midpoint velocity before drift and admit real stopping/impact roots. For steady sliding, candidate x=uH−.5mu*g*H², whereas strict macro x=uH, and four endpoint substeps x=uH−mu*g*H²*(pieces−1)/(2pieces). Strict physical position errors are1.090mm macro / .273mm four-step for sliding, .818mm macro for stopping, and7.357mm macro /1.539mm four-step for impact, all above the unchanged macro physical position bound. No equally accurate gain is claimed against these references. Failed strict transactions are retained as negative evidence; candidate qualification did not fail.

## 30/60 Hz interpretation

All24 warmed candidate samples per fixture/path are below16.667ms and therefore also33.333ms. The slowest warmed candidate API sample is13.941ms, leaving2.726ms of a16.667ms CPU budget or19.393ms of a33.333ms budget for other work. Candidate first-call latency (context construction excluded) is reported separately, n=3 per fixture/path; the largest observed first call was16.642ms. These finite observations are not worst-case guarantees. Rendering, input, other simulation and context/setup costs are excluded.

The owner accepts a fixed1/30s macro and rejects1/60s: fitting a60Hz wall-clock budget does not make it a qualified60Hz simulation API. The four strict holding substeps take18.860–19.000ms median: they fit33.333ms but exceed16.667ms in every warmed observed sample. Strict macro holding is faster than the candidate. The difficult multibody fixture remains unresolved by this narrow path; there is no stack, rotation, turning/reversal, finite-floor-transition or broad-engine claim.

## Resources, preservation and seal

Actual measured GPU: NVIDIA GB10, driver615.71.09; normal hardware settings. Candidate launches six kernels per complete call (force command3, reconciliation1, advance1, commit1), versus20 strict macro or80 four-substep kernels. Candidate advance is grid1/block1,255 registers/thread, zero declared static/dynamic shared memory. CUPTI reports localMemoryPerThread0 and localMemoryTotal180,879,360 bytes for that kernel on both paths. These metadata fields do not establish zero dynamic spills or a measured allocation/footprint. Dynamic spills/stalls remain unmeasured; denied Nsight Compute counters were never retried. The owner retains ten explicit buffers /50,168 bytes.

All 18,855 protected hashes,5,901 asset/save size/mtime identities,17 campaign source hashes and119 unrelated source/lock hashes match. Pinned Mojo1.2.0.dev2026092905 and isolated MAX26.7.0.dev2026092905 metadata hashes match. Minimum available memory 110.307GiB; final 113.426GiB, above the32GiB reserve. One execution/GPU slot, one-thread builds, one-CPU precompile and finite180s build/30s native guards were maintained. H3 remains paused and untouched; no installs or hardware/driver/power/security/profiling-permission changes.

Initial benchmark-helper compile and fresh-package namespace setup errors are retained; they were corrected before corresponding native measurement, without editing physics. All72 preflight records,360 validated plain timing records and72 validated traced records are saved. No owned jobs or GPU compute processes remain.

Evidence: `verification.json`, `performance.json`, `correctness-barrier.json`, `preservation-and-idle-audit.json`, predeclared protocol, source/fresh-package benchmarks and fingerprints, JSON outputs, logs, guard telemetry,12Nsight Systems reports/SQLite exports and `FINAL-SHA256SUMS`.
