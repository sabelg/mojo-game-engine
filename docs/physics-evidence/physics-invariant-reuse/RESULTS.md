# Bounded invariant-matrix reuse: exact A/B qualification

The isolated opt-in `GpuCachedCoupledBoxResponse` rebuilds normal/tangentNT and tangent/tangentTT effective-mass blocks once per selected patch after projection/contact reconstruction. Existing APIs, laws, precision, iteration policies and convergence gates remain unchanged. Original source/executables and prior baseline receipts stay available for A/B.

## Correctness before timing

All70 original trajectories in both source/fresh-precompiled modes have byte-identical initial, result and complete response traces (140 cases). All80 correctness-only profiling sample records also match original baseline canonical records exactly; the monotonic clock was disabled in those runs. Target tangent bases0/45/90, seed61 rank3/permutation witness, conditioning/Jacobian/nonfinite/configuration/rollback and18 matrix-cache mutation proofs pass. Original full qualification remains63/70; two baseline64 rejects, four old ledge event gaps and strict SAME-TIME translated case68 remain.

The320 total canonical sample records (80 correctness-only plus240 timed A/B across source, CUDA/NVTX andfreshprecompiled) preserve complete raw body buffers, impulses, residual histories, energy/residual reports and actual work counters. No non-bitwise numerical discrepancy was accepted.

NT/TT depend on fixed mass/inertia, postprojection COM/orientation, reconstructed contact points/normal and tangent basis. Velocity, impulses, active-normal selection, pressures, disk radii, residuals and Jacobians still change and are recomputed. Response stores change velocity only; fields0..10 are verified unchanged through velocity solving. Direct reassembly from post-solve bodies matches every cached block, unused pad and canary bit. Live-body mass/inertia edits are forbidden by existing error15; tests preserve exact rejection then change mass byremove/recreate with a new generation. Pose, shape revision/resize, local orientation, basis/material changes, contact loss, mu0 and foreign/stale handles are exercised.

Each positive-friction resolve clears all1536 payload words and repacks active matrices after fresh contact reconstruction. No prior resolve/generation/revision is trusted. The private buffer persists only as allocation storage; its data are not reused across calls. mu0 consumes no cache and keeps the original normal branch. Fallback/residual tangent_metric formulas remain unchanged; TT diagonals are not substituted for differently ordered formulas. NN and normal-mask operators were already cached and are unchanged.

The initial mutation test intentionally retained here hit error15 because it attempted an unsupported mass update; two preceding cache cases passed exactly. Its executable/source/logs remain in`cache-attempt-1`. The corrected test obeys the existing lifecycle rule. There was no cache/state mismatch and no lowered physical gate.

## Same bounded warmed A/B methodology

One first call, two excluded warmups, seven warmed independently reset samples per fixture/variant/path. Source plain, NsightSystems CUDA/NVTX and fresh precompiled API were all rerun for both original and cached variants. Numerical checks run after every call. Time includes existing status/report mappings and waits; CPU replay, snapshots/counters/history, JSON and reset commands stay outside step+response scopes. Compilation, setup/context/uploads, first call and warm execution are separate. No cache/clock/settings flush was forced; first call is not an empty-driver-cache claim.

|Workload|Source original ms median [range]|Source cached ms median [range]|Observed source median reduction|Precompiled original→cached ms medians|GPU kernel-sum original→cached ms medians|
|---|---|---|---|---|---|
|coupled sliding target|1350.252 [1347.674–1359.035]|1135.324 [1079.578–1140.825]|15.92%|1367.395→1152.824|1352.697→1139.254|
|centered box/floor normal|4.149 [3.806–6.173]|4.260 [4.152–5.523]|-2.67%|4.260→4.156|4.117→4.034|
|centered two-body rebound|211.668 [209.310–217.255]|75.606 [73.225–76.870]|64.28%|213.623→77.535|210.968→76.234|
|separated no-contact|1.773 [1.677–2.713]|1.695 [1.691–3.206]|4.37%|1.681→1.758|1.550→1.553|

The coupled target has about15.7–15.9% lower observed warmed API medians in these source/precompiled/trace runs. The centered rebound has about63.7–64.3% lower medians. Each comparison is the same physical fixture and same solver work. Cheap normal/no-contact controls have overlapping and mixed host ranges; no reliable benefit is claimed for them. The no-contact GPU total rises byabout0.003ms from the extra empty cache-pack, despite host noise sometimes favoring the candidate. Seven samples support observed median/range only, not a p95, confidence interval or broad workload speedup.

|Variant / workload|Actual velocity / position sweeps|Coupled attempts / Newton / residual evaluations|GPU velocity kernel ms median [range]|Cache-pack GPU ms median [range]|Kernel launches / synchronization APIs|
|---|---|---|---|---|---|
|baseline / coupled sliding target|96 / 23|192 / 505 / 2707|1341.900544 [1339.908256–1352.698400]|none|[17] / [25]|
|cached / coupled sliding target|96 / 23|192 / 505 / 2707|1127.899104 [1124.480192–1137.697408]|1.975968 [1.973408–2.352576]|[18] / [25]|
|baseline / centered box/floor normal|1 / 1|0 / 0 / 0|0.139104 [0.138944–0.152352]|none|[17] / [25]|
|cached / centered box/floor normal|1 / 1|0 / 0 / 0|0.148832 [0.139808–0.497664]|none|[17] / [25]|
|baseline / centered two-body rebound|96 / 1|96 / 0 / 192|206.397280 [205.127392–208.607104]|none|[17] / [25]|
|cached / centered two-body rebound|96 / 1|96 / 0 / 192|70.869824 [66.400736–71.487296]|1.300320 [1.299968–1.631648]|[18] / [25]|
|baseline / separated no-contact|0 / 1|0 / 0 / 0|0.015072 [0.015040–0.016256]|none|[17] / [25]|
|cached / separated no-contact|0 / 1|0 / 0 / 0|0.014944 [0.014944–0.024384]|0.003456 [0.003424–0.004064]|[18] / [25]|

Target work stays96 sweeps,192 coupled attempts/accepted,0 legacy fallbacks,505 Newton corrections,2707 residual evaluations,505 complete-pivot solves,1853 halving evaluations,rank sum4016/max8,0 profile rejects. Position sweeps remain23 of the unchanged64 budget. Selected2 patches now assembleNT/TT twice per resolve instead of192 times; the same96-sweep schedule and local8/16 bounds remain. For the centered rebound,96 sweeps/attempts and192 residual evaluations remain, with0 Newton corrections. This shows the improvement is removed invariant work, not altered convergence.

## GPU phases, host API waits and cache cost

Device phases use exact CUDA correlation IDs within host NVTX scopes, with integration3 and response14/15 ordered launches checked for every sample. Truncated symbol hashes and grid/block consistency are retained; short cross-clock timestamp offsets do not alter duration classification. All physics kernels remain at original launch geometry, including cached velocity and cache-pack grid1/block1. No broader parallelism was introduced.

|Traced target phase median ms|Original|Cached|
|---|---|---|
|integration_GPU_ms|0.191648|0.191808|
|registry_reconciliation_GPU_ms|0.085440|0.085152|
|geometry_pairs_GPU_ms|0.485184|0.473760|
|position_projection_GPU_ms|4.588064|4.163488|
|constraint_packing_GPU_ms|4.865408|4.267488|
|invariant_cache_pack_GPU_ms|0.000000|1.975968|
|velocity_response_GPU_ms|1341.900544|1127.899104|
|validation_commit_GPU_ms|0.207232|0.207040|
|launch_API_ms|0.036128|0.039008|
|synchronization_wait_API_ms|1352.762464|1139.384016|
|memory_copy_API_ms|0.030336|0.030624|

Synchronization API durations include GPU waiting and overlap kernels; they are not additive overhead. Extra diagnostic mappings are measured separately and excluded from step+response. Existing logical copy payload remains9,376bytes each way in API scopes and50,816bytes each way in external diagnostics. Kernel metadata/register/local-memory totals are not used to claim a spill/occupancy or instruction-level explanation. The cached target remains expensive and dominated by the velocity solver, not a general real-time solution. Rendering/broadphase inference and PhysX comparisons are absent.

## Compile/setup/cold and memory

|Variant / path / fixture|Setup+uploads ms|First step+response ms|Warmed API ms median [range]|
|---|---|---|---|
|baseline / plain / 0|813.192|1364.514|1350.252 [1347.674–1359.035]|
|baseline / trace / 0|785.146|1366.970|1352.869 [1350.468–1362.859]|
|baseline / packaged / 0|791.478|1378.087|1367.395 [1354.873–1375.304]|
|cached / plain / 0|801.260|1147.500|1135.324 [1079.578–1140.825]|
|cached / trace / 0|778.370|1145.327|1139.498 [1136.210–1151.142]|
|cached / packaged / 0|800.669|1156.650|1152.824 [1140.480–1158.232]|
|baseline / plain / 1|744.483|12.374|4.149 [3.806–6.173]|
|baseline / trace / 1|776.779|12.491|4.300 [4.007–6.171]|
|baseline / packaged / 1|747.700|11.534|4.260 [3.816–5.741]|
|cached / plain / 1|755.310|11.407|4.260 [4.152–5.523]|
|cached / trace / 1|803.364|13.947|4.200 [4.169–5.887]|
|cached / packaged / 1|755.807|12.508|4.156 [4.104–4.932]|
|baseline / plain / 2|753.320|227.674|211.668 [209.310–217.255]|
|baseline / trace / 2|787.605|228.708|211.140 [209.830–212.758]|
|baseline / packaged / 2|750.824|231.698|213.623 [211.957–216.304]|
|cached / plain / 2|759.035|89.122|75.606 [73.225–76.870]|
|cached / trace / 2|782.233|91.418|76.362 [71.940–77.907]|
|cached / packaged / 2|746.803|88.480|77.535 [71.914–78.611]|
|baseline / plain / 3|745.973|18.221|1.773 [1.677–2.713]|
|baseline / trace / 3|778.250|18.617|1.716 [1.713–2.182]|
|baseline / packaged / 3|738.471|18.591|1.681 [1.670–2.487]|
|cached / plain / 3|755.614|16.859|1.695 [1.691–3.206]|
|cached / trace / 3|816.761|18.343|1.678 [1.674–2.097]|
|cached / packaged / 3|752.390|16.819|1.758 [1.647–1.951]|

|Build stage|Guarded host wall s|
|---|---|
|package-precompile|5.245|
|baseline-timed-source-compile|18.068|
|cached-timed-source-compile|16.438|
|baseline-timed-packaged-compile|16.383|
|cached-timed-packaged-compile|14.794|

The new1538Float64 buffer adds exactly12,304bytes (12KiB payload +16canary bytes). Explicit target device storage grows from3.485493MiB to3.497227MiB (66→67 constructor buffers); mu0 still allocates that private buffer but avoids its pack/velocity use. Positive-mu adds one serial launch, whose measured target cost isabout1.976ms median (including zeroing/padding), centered impact1.300ms, no-contact0.003456ms. Original body/status/report readbacks and synchronization count25 stay unchanged.

Maximum sampled compute process footprint: baseline983MiB device /2976.2MiB RSS; cached929MiB device /2921.5MiB RSS. These include context/modules/runtime pools/profiler/cache, sampled roughlyevery.5s with observer overhead, and are not guaranteed instantaneous peaks. Static cache bytes are the attributable storage change. Memory-usage tracing, CPU sampling and context-switch tracing were disabled;32GiBreserve retained.

## Scope and use

Opt in explicitly: `experimental.physics_gpu.cached_coupled_response.GpuCachedCoupledBoxResponse`. Original `GpuCoupledBoxResponse`, recommended/default Atlas APIs and SDK are unchanged. Correctness/coverage are bounded by the same original domain and63/70 limitations. Independent12/12ledge and75/75translated-boundary suites remain separate. No new features, solver-law changes, installs, OS/driver/firmware/power changes, broader parallelism or PhysX claims. H3stays paused. Stop here; this checkpoint implements only resolve-local invariantNT/TT reuse.

Evidence: `INVARIANTS.md`, `MASS_LIFECYCLE_CLARIFICATION.md`, `correctness-comparison.json`, `measured-AB.json`, source/precompiled70-case traces, target/rank/validation/cache outputs, standalone A/B harnesses and executables, `.nsys-rep`/SQLite captures, `*-GPU-phases-fixture-*.json`, final`verification.json` and`SHA256SUMS`. Original baseline receipts/code/failed fixtures remain preserved by hash.
