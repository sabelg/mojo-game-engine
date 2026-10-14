# Lossless active-mask packing: sealed bounded result

Separate opt-in GpuPackedOperatorBoxResponse against the qualified shared-operator owner. No warm-start plumbing, seeds, temporal solver, precision/rank/pivot change or automatic replacement is included. The sixteen normal-mask4x4 pseudoinverse blocks are transported compactly and reconstructed into the original256-word shared/local layout. Every stored Float64 bit, invalid mask, mask order, zero product, arithmetic/reduction/tie decision, barrier, cap and early-inner/final gate is retained. The nonlinear tangent Jacobian is unchanged and still uses complete pivoting.

Codec:360 source/package tables over 0..4 points and all masks,1,800 normal-controller read comparisons, negative/quiet/signalingNaN/inf bits, rank deficiency/invalid flags, asymmetrical stored active bits, shared/local decode, neighboring poison, arena guards and scratch reuse. Full correctness:140 byte-exact source/package trajectories,six basis checks,9,792 bit-exact controller records across cooperative/leader modes,80 clock-disabled complete-owner records,source/package rank/derivative/rejection/lifecycle/rollback and 186 regressions. All 480 timed records also matched numeric/work outputs exactly. Original 63/70 accounting and known failures remain unchanged. Initial test floating-typing and module header frontend errors are retained; neither was a native correctness failure, and no successful command was duplicated.

|Path / fixture|Shared baseline API median ms|Packed API median ms|Median paired delta ms|Median paired change|Verdict|
|---|---:|---:|---:|---:|---|
|source / difficult coupled sliding|473.6849|473.9727|+1.1004|+0.233%|mixed/inconclusive|
|source / zero-friction floor|4.3862|4.2483|-0.1266|-2.775%|mixed/inconclusive|
|source / centered rebound|48.0394|47.0512|-0.6131|-1.284%|repeatable faster in bounded protocol|
|source / empty separated bodies|1.6671|1.6554|-0.0037|-0.223%|mixed/inconclusive|
|packaged / difficult coupled sliding|474.0534|472.5714|-2.1777|-0.459%|mixed/inconclusive|
|packaged / zero-friction floor|4.2349|4.2299|-0.0026|-0.060%|mixed/inconclusive|
|packaged / centered rebound|46.4524|46.0495|-0.4117|-0.883%|mixed/inconclusive|
|packaged / empty separated bodies|1.7639|1.7087|-0.0451|-2.558%|mixed/inconclusive|

Twelve measured pairs per fixture/path, four batches with balanced orders. First/warm-up exclusions were fixed before timing. Paired medians need not equal differences between marginal medians. Faster/slower verdict requiresat least 10/12 signs and all four batch medians; no favorable reruns,p95/population confidence or general-scene claim.

|Fixture|Baseline GPU packing ms|Packed GPU packing ms|Baseline GPU velocity ms|Packed GPU velocity ms|
|---|---:|---:|---:|---:|
|difficult coupled sliding|4.489152|4.501952|462.092512|459.055136|
|zero-friction floor|2.368000|2.364352|0.140896|0.132576|
|centered rebound|2.484256|2.502432|40.028800|39.639904|
|empty separated bodies|0.235328|0.234464|0.014976|0.015136|

CUDA/NVTX activity correlation supplies seven warmed GPU observations per owner/fixture. Encode and decode costs are included in packing and velocity kernels; they are not separately isolated. Kernel launch counts/order remain 18 (nonzero friction) or 17 (zero friction); no extra GPU stage is inserted. Copies/API waits,plain/traced observations,register/local-memory metadata and cold/setup samples are retained. Synchronization overlaps GPU work. Declared local-memory/register metadata is not dynamic spill/stall traffic; counters remain unmeasured and the denied counter request was not retried.

Representation:normal live payload words 0, 1, 6, 24, 80 for 0..4 points; all original bits outside the structural set must be positive zero for compact mode. Any exception uses dense fallback and preserves all 256 words. Perpatch index metadata is18 Int32 words = 72 bytes (mode,payloadcount,16starts). Fourpoint compact transport is640+72 = 712 bytes versus2,048 dense payload bytes (65.234375%fewer payload-plus-metadata bytes), before unchanged mask flags. Dense fallback is2,048+72 = 2,120 bytes. A 256-word arena per patch is retained for worst-case fallback:32,784 bytes including guards, unchanged. New metadata allocates 1,160 bytes in one buffer; fixed total allocation therefore grows to33,944 bytes. Shared memory stays 4,176 bytes. Stale compact arena tails are ignored using current mode/offsets; initialization and guards remain explicit.

|Path / fixture|Measured payload words|Measured metadata bytes|Dense fallback patch observations|
|---|---|---|---:|
|source / difficult coupled sliding|[160.0]|[144.0]|0.0|
|source / zero-friction floor|[80.0]|[72.0]|0.0|
|source / centered rebound|[80.0]|[72.0]|0.0|
|source / empty separated bodies|[0.0]|[0.0]|0.0|
|packaged / difficult coupled sliding|[160.0]|[144.0]|0.0|
|packaged / zero-friction floor|[80.0]|[72.0]|0.0|
|packaged / centered rebound|[80.0]|[72.0]|0.0|
|packaged / empty separated bodies|[0.0]|[0.0]|0.0|

Difficult fixture has two four-point patches, so 160 payload words +144 metadata bytes per call. Each call is one 1/30 s physical step, retaining 96 sweeps, 429 solves, 2,102 evaluations, 1,315 trials and nine fallback uses of the original solver. Dense codec fallback is a distinct bit-preservation path and is reported separately. No algebraic symmetry mirroring, skipped zero arithmetic or matrix-factor substitution is used.

All 13,027 protected hashes, 5,901 asset/save identities, 17 campaign sources, 119 other source/lock hashes and Mojo 1.2.0.dev2026092905 / MAX 26.7.0.dev2026092905 pins verified unchanged, including both prior experiment seals. Actual host Lenovo 30KL0002US, aarch64/NVIDIA GB10. Minimum available memory 109.836GiB above32GiB reserve. One execution slot,single-thread builds,finite guards,normal settings and H3pause preserved. No dependencies,drivers,power/security/profiling permissions or retired cutoff changes.

Checkpoint:verified experiment complete; no running command,owned job,GPU compute app or remaining blocker. Original owners and the cache stage remain available. No combination or default replacement is made. Evidence:verification.json,correctness-barrier.json,measured-performance.json,codec/controller/rank/basis/trajectory/regression outputs,build/telemetry/trace receipts,LAYOUT.md and FINAL-SHA256SUMS.
