# Seeds-disabled cache plumbing: sealed result

Implementation complete: separate opt-in GpuWarmPlumbingBoxResponse, with tracked registry/collision/detection owners beneath it. Existing owners, kernels, modes, launch arguments and packing remain unchanged. Bounded committed/pending cache, full identity/revision/epoch eligibility, canonical impulse sign and anchor transforms, unique mapping, cold capacity/ambiguity handling, rejection and repeated-resolve behavior are implemented. Seeds are disabled on every path and no cache data reaches the solver.

Correctness: 140 byte-exact source/fresh-package trajectories, six basis checks, 80 exact clock-disabled complete-owner records, 48 controlled mapping cases checking 9,338 immutable solver-input words each, source/package tracked registry/collision/exhaustion tests, cooperative/leader cache protocols, 32 independent CPU edge-step checks and 186 regressions. Retained 9,792 controller records have unchanged solver dependencies. All physical/residual/energy/cone/rollback gates, caps and early-inner policy remain unchanged. Original 63/70 accounting and known failures remain. All 560 timed canonical records also matched numerics and work exactly.

The real clustered three-point support fixture correctly stays cold under ambiguous matching. Its first two positive-hit test assumptions were corrected without changing eligibility gates, with negative logs retained. A unique edge-contact trajectory exercises real hits, basis/normal changes and cold misses. A packaged test-only helper import error was repaired by inlining its unchanged helpers; completed successful stages were preserved. Two overbroad target/rank fingerprints included an excluded, unimported test file whose syntax was repaired: unchanged binaries/package and absence of that module were proved in unused-test-fingerprint-audit.json, without rewriting receipts or rerunning those commands.

|Path / fixture|Baseline API median ms|Plumbing API median ms|Median paired added ms|Median paired change|Verdict|
|---|---:|---:|---:|---:|---|
|source / difficult coupled sliding|446.0845|444.4381|-1.6180|-0.363%|mixed/inconclusive|
|source / zero-friction floor|3.8160|4.0664|+0.1159|+3.039%|repeatable added overhead in bounded protocol|
|source / centered rebound|43.6566|43.8027|+0.1464|+0.336%|mixed/inconclusive|
|source / empty separated bodies|1.6491|1.7095|+0.0604|+3.664%|repeatable added overhead in bounded protocol|
|source / consecutive unique edge contact|30.9641|30.8311|-0.0899|-0.291%|mixed/inconclusive|
|packaged / difficult coupled sliding|445.6658|446.0702|+1.0017|+0.225%|mixed/inconclusive|
|packaged / zero-friction floor|3.8163|4.0658|+0.1160|+3.045%|repeatable added overhead in bounded protocol|
|packaged / centered rebound|43.6030|43.6797|+0.1614|+0.371%|repeatable added overhead in bounded protocol|
|packaged / empty separated bodies|1.6476|1.7097|+0.0620|+3.757%|repeatable added overhead in bounded protocol|
|packaged / consecutive unique edge contact|30.8152|30.8234|-0.0311|-0.101%|mixed/inconclusive|

Median paired differences are computed per paired call; they need not equal differences between marginal medians. Twelve measured pairs per path/fixture, four balanced batches; first/warm-up exclusions fixed by the scripts before measurements. No favorable reruns. Light controls show added cost; difficult and edge results are mixed, so no solver speedup claim. Source and package edge trajectories each recorded 8 hits in 12 measured lookups; seeds still stayed zero and work stayed exact. The first four fixtures reset identical response-entry states; the fifth evolves each owner independently over consecutive physical steps, without resets.

|Fixture|Cache begin GPU ms|Prepare/lookup GPU ms|Publish GPU ms|Integration tracking GPU ms|
|---|---:|---:|---:|---:|
|difficult coupled sliding|0.001408|0.077856|0.120896|0.001184|
|zero-friction floor|0.001408|0.040832|0.052256|0.001216|
|centered rebound|0.001408|0.040832|0.052128|0.001184|
|empty separated bodies|0.001408|0.005568|0.053216|0.001216|

GPU phase values use permitted CUDA/NVTX activity correlation and seven warmed samples per owner/fixture. Four extra kernel launches per physical step were verified. Preparation includes clearing and staging as well as lookup; publication includes copying. Profiles use the isolated controls, not the edge hit trajectory. Baseline/plumbing GPU solver medians for the difficult control were 433.0322/433.5067 ms; rebound 38.3431/38.3422 ms. Synchronization waits overlap GPU execution. Registers/local-memory declarations and sampled host/device memory are not dynamic spill/stall measurements; those remain unmeasured. No denied-counter retry, p95/population confidence or general-scene claim.

Fixed explicit added storage: 13 GPU buffers / 20,024 bytes (2,160 tracking +17,864 cache/mapping/diagnostics). Solver shared allocation remains 4,176 bytes. Reset UPDATE tracking is outside the selected physical-step wall; setup/cold observations and that instrumentation scope remain explicit.

Preservation: 10,714 protected hashes, all 5,901 asset/save identities, 17 campaign sources, 119 other source/lock hashes, pinned Mojo 1.2.0.dev2026092905 and isolated MAX 26.7.0.dev2026092905 unchanged. Actual host: Lenovo 30KL0002US, aarch64 / NVIDIA GB10. Minimum available memory 110.839 GiB; 32 GiB reserve maintained. Single slot, one-thread builds, finite guards, normal settings, H3 paused. No dependencies, drivers, power/security/profiling permissions or retired thermal-cutoff changes.

[Final later seed contract](SEED_CONTRACT.md): canonical sign/anchors; cached normal only screens eligibility; current pressure/material define the disk; actual applied accumulation starts zero; consume once; side-effect-free body/accumulator trials; complete cold restoration and separate attempt diagnostics; runtime checks only; alternate roots failing strict offline physical gates block warm acceptance. Later qualification requires both identical-entry paired solves and genuine independently evolving trajectories. No seed implementation is included.

[Next experiment queue](NEXT_EXPERIMENTS.md): lossless active-mask packing next on its own opt-in baseline, qualified/timed separately; warm enablement and native temporal/TGS-style solving remain later separate stages. No packing or temporal implementation has started.

Checkpoint: implementation, qualification and bounded measurement complete; no running command, owned job, GPU compute app or remaining blocker. Last native stage profile-plumbing-trace-fixture-3 took 3.142 s and returned zero. Evidence: verification.json, correctness-barrier.json, measured-performance.json, all source/package receipts, traces, negative evidence, protocol documents and FINAL-SHA256SUMS.
