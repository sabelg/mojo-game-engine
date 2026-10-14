# Qualified opt-in cooperative point solver: bounded results

A separate GpuCooperativeBoxResponse keeps the retained tangent-cache law and parallelizes only per-point residual/Jacobian rows within a persistent32-lane block. All previous modes and defaults remain. The qualified difficult target benefits; centered rebound regresses versus the retained serial tangent-cache mode. Keep explicit modes and make no general crossover, real-time, independent-island or PhysX claim.

## Exact qualification

280original trajectory comparisons are byte-identical:70source+70fresh-package for cooperative and the same140for the leader-only control, including existing failure outcomes. Both modes pass source/package bases0/45/90, derivative/configuration/profile/energy/state/rollback and cache-mutation/generation/stale/foreign/immutable-mass gates. The four source/package controller runs reproduce9792protected records on the102case count0..4/Jacobian/partial-output/inactive-lane/reuse corpus.160clock-disabled full-owner records and all prior retained samples match.186affected regressions pass:75boundary+12ledge each source/package plus12retained unchanged collision/response/lifecycle/island/sleep dependencies. All720timed records also match original canonical state, raw buffer, impulses, history, energy and work. No numerical difference was accepted.

Original coverage stays63/70: strict translated SAME-TIME failure, two baseline64 convergence rejects and four old ledge gaps are retained. Separate75/75translation and12/12ledge suites do not inflate it. See correctness-barrier.json, BARRIER_AUDIT.md and full-solver-generated-behavior.json. The audit is finite; invalid-direction and final BR_ENERGY branches were source-audited without dedicated forced execution.

## Fixed interleaved host/API wall timing

Integration+resolve milliseconds, median [minimum,maximum],12warmed samples permode/fixture/path. Four independent process batches use all six orders twice. Each owner/batch excludes one firstcall and one warmup, then records3measured calls:240calls perpath,480total. Setups/resets/CPU or analytic checks/extra diagnostics/rollback are outside timing; existing API waits remain inside. Three persistent contexts in one process are an assessment configuration, not a production scene benchmark. First-owner setup includes common runtime startup; construction order is not balanced and setup costs cannot rank modes. No forced cold-cache resets.

|Path / fixture|Serial tangent cache|Leader-only block|Cooperative block|Cooperative paired effect vs serial|
|---|---:|---:|---:|---|
|source / coupled sliding target|1106.121 [1096.923, 1124.170]|1371.990 [1353.480, 1389.959]|734.879 [730.261, 751.856]|-33.58%, 12 faster/0 slower; repeatable faster in bounded protocol|
|source / zero-friction floor|4.388 [4.210, 5.714]|4.259 [4.108, 5.572]|4.624 [4.246, 6.268]|+3.41%, 4 faster/8 slower; mixed/inconclusive|
|source / centered rebound|46.474 [44.399, 48.446]|65.821 [63.421, 68.458]|58.362 [56.809, 60.784]|+27.13%, 0 faster/12 slower; repeatable slower in bounded protocol|
|source / empty separated bodies|1.747 [1.676, 2.956]|1.764 [1.647, 1.984]|1.767 [1.650, 3.217]|+2.75%, 5 faster/7 slower; mixed/inconclusive|
|packaged / coupled sliding target|1113.822 [1103.962, 1142.383]|1378.560 [1357.249, 1401.231]|742.710 [731.276, 767.402]|-33.14%, 12 faster/0 slower; repeatable faster in bounded protocol|
|packaged / zero-friction floor|4.842 [3.822, 6.219]|4.260 [4.184, 5.889]|4.367 [4.149, 6.117]|-2.88%, 6 faster/6 slower; mixed/inconclusive|
|packaged / centered rebound|47.245 [44.759, 48.635]|66.774 [62.749, 68.953]|59.681 [57.189, 62.229]|+27.32%, 0 faster/12 slower; repeatable slower in bounded protocol|
|packaged / empty separated bodies|1.770 [1.640, 2.680]|1.896 [1.649, 2.982]|1.728 [1.648, 2.575]|-3.85%, 8 faster/4 slower; mixed/inconclusive|

Paired effects are median within-cycle ratios/differences. Negative means candidate faster. Repeatability requires>=10/12same signs and all4batch delta medians agreeing; it is an operational rule, not statistical confidence. The leader-only control retains the same staging, barriers, debug counters and serial control. Its delta versus retained serial includes their combined cost and code-generation/resource effects, not pure barrier time.

## Device versus API and tracer effect

The same fresh-package binary runs plain and with the existing CUDA/NVTX settings:1firstcall+2warmups excluded,7warmed samples each, fourfixtures/three modes;120plain+120traced calls. Device duration uses CUDA activities correlated with the original NVTX API phases. Synchronization API durations overlap device work and must never be added as separate overhead. Host-minus-kernel includes queue gaps/readbacks/launches and is not a uniquely measured CPU cost.

|Fixture / mode|Solver GPU ms [range]|GPU kernel sum ms [range]|Plain API ms [range]|Traced API ms [range]|Observed trace–plain ms / %|
|---|---:|---:|---:|---:|---:|
|coupled sliding target / serial|1089.228 [1083.335, 1098.273]|1101.772 [1096.641, 1111.841]|1114.713 [1105.291, 1140.366]|1101.964 [1096.844, 1112.169]|-12.749 / -1.14%|
|coupled sliding target / leader|1342.762 [1338.252, 1367.421]|1356.332 [1352.013, 1379.309]|1369.623 [1365.331, 1405.689]|1356.522 [1352.571, 1379.522]|-13.102 / -0.96%|
|coupled sliding target / coop|726.885 [719.327, 745.069]|739.886 [732.431, 757.474]|740.434 [731.867, 759.935]|740.071 [732.608, 757.654]|-0.364 / -0.05%|
|zero-friction floor / serial|0.147 [0.140, 0.151]|4.044 [4.011, 4.664]|4.319 [4.094, 5.311]|4.206 [4.177, 5.922]|-0.113 / -2.62%|
|zero-friction floor / leader|0.148 [0.140, 0.151]|4.046 [4.026, 4.562]|4.392 [4.110, 6.686]|4.214 [4.191, 5.346]|-0.178 / -4.04%|
|zero-friction floor / coop|0.147 [0.140, 0.160]|4.204 [4.026, 5.414]|4.180 [4.139, 5.420]|4.378 [4.194, 6.386]|+0.197 / +4.72%|
|centered rebound / serial|39.935 [38.937, 41.458]|45.877 [44.584, 47.019]|46.049 [44.849, 48.618]|46.048 [44.757, 47.196]|-0.001 / -0.00%|
|centered rebound / leader|59.601 [58.378, 62.008]|65.479 [64.473, 68.492]|65.459 [63.423, 67.090]|65.661 [64.626, 69.459]|+0.202 / +0.31%|
|centered rebound / coop|51.389 [49.499, 54.000]|56.960 [55.590, 59.570]|58.724 [58.085, 59.490]|57.095 [57.016, 59.733]|-1.629 / -2.77%|
|empty separated bodies / serial|0.015 [0.015, 0.016]|1.551 [1.550, 2.102]|1.646 [1.641, 2.753]|1.805 [1.714, 2.754]|+0.159 / +9.68%|
|empty separated bodies / leader|0.016 [0.015, 0.017]|1.562 [1.555, 2.184]|1.684 [1.647, 2.473]|1.692 [1.681, 3.482]|+0.008 / +0.45%|
|empty separated bodies / coop|0.015 [0.015, 0.017]|1.555 [1.555, 2.071]|1.697 [1.696, 2.498]|1.681 [1.679, 2.971]|-0.016 / -0.95%|

These tracer deltas are observed same-binary aggregate changes across separate process runs with variance; neither positive nor negative values are a pure instrumentation cost estimate. Clock/NVTX marker cost is not isolated. Debug counters and canaries remain enabled; no unqualified no-debug variant was added. Source/package interleaving supplies the primary API comparison, and phase tracing independently supplies device attribution. No instruction-level or spill cause is inferred.

## Target phase, synchronization and memory evidence

|Mode|Target solver GPU ms|Cache-pack GPU ms|Launch API ms|Sync wait API ms|Kernel launches / wait calls|
|---|---:|---:|---:|---:|---|
|serial|1089.228|2.358|0.039|1101.836|[18] / [25]|
|leader|1342.762|2.455|0.039|1356.395|[18] / [25]|
|coop|726.885|2.459|0.038|739.958|[18] / [25]|

Both32-lane variants retain the same kernel launch schedule and authoritative commit as the serial tangent cache; positive-mu18launches, mu0normal17. The existing host coefficient==0branch remains. The cooperative target still has96sweeps,192attempts,505Newton/linear solves,2707evaluations and1853halving trials; timings reflect execution changes, not fewer algorithmic steps. Centered rebound has no Newton corrections and only192evaluations; its much cheaper roots do not amortize the new coordination/staging cost. This is a source-supported explanation, not a measured instruction breakdown.

Explicit additional owner storage is one18Int64debug buffer,144global bytes, with4176static shared bytes perblock. The existing14608byte tangent cache stays unchanged. Each resolve zeroes the debug buffer asynchronously; no extra in-API host/device synchronization was added. Debug writes and whole-block control are included in measured time. PTX declares two local storage areas3312/5536bytes; these are not measured allocator peaks or dynamic spill traffic. The full solver emits13staticbarrier sites; per-output Float64 grouping/order, serial masks/pivots/reductions/decisions and ordered body writes are retained. Neither FP32 arithmetic nor atomics appears in that kernel diagnostic.

Sampled process memory includes context/runtime/JIT/code caches; it is not attributable to144bytes or a guaranteed peak. Sampling is roughly0.5s and can miss transients. Exact storage sizes above remain the authoritative incremental counts.

- serial: sampled device max 929 MiB; host RSS max 2992012 KiB.
- leader: sampled device max 1047 MiB; host RSS max 3112376 KiB.
- coop: sampled device max 1047 MiB; host RSS max 3112696 KiB.

## Decision and scope

Retain this prototype as explicit opt-in for the qualified expensive connected workload. The predeclared target benefit rule is applied against both serial and leader-only controls; report it in verification.json. Do not automatically switch based on pair counts or infer that independent-island concurrency accelerates this one connected problem. Centered rebound and cheap controls keep the retained serial mode available. No further solver operation, precision/budget/policy change, defaults, dependencies or features were introduced.

All earlier source, packages, baselines and receipts remain. Pins, normal settings,5901asset/save identities, campaign/SDK/dirtywork/locks andH3pause are preserved. Final fingerprints, finite one-thread180s builds/30s runs/32GiBreserve and idle cleanup are in verification.json and FINAL-SHA256SUMS. Intermediate frontend corrections, the paused checkpoint and diagnostic filename-selection correction are retained; none changed numerical acceptance.
