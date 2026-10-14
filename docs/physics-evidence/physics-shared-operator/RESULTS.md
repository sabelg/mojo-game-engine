# Shared operator-table placement: bounded result

Only the original 256-Float64 mask table moved from a local array into existing shared slots 113–368. The separate opt-in GpuSharedOperatorBoxResponse retains the early-inner policy, arithmetic, initialization, mask selection, pivots, barriers, inactive/rejection paths and final gates. Total shared allocation remains 4,176 bytes, with zero additional global/owner buffers. The table loads once per patch visit, not once per physical step. No compression or warm starting was implemented.

Actual hardware: aarch64, NVIDIA GB10, 615.71.09, 37, 5.85 W. Host inventory reports Lenovo model 30KL0002US. The selected source explicitly requires NVIDIA GB10 and the receipts identify the measured host directly.

Exact correctness: 140 source/fresh-package trajectories, six basis checks, source/package rank/derivative/rejection/cache/lifecycle/rollback, 9,792 controller records (including all 256 table words and adjacent poison checks), 80 clock-disabled complete-owner records, and 186 affected/dependency regressions. Complete numeric, work, state, history, status, impulse and controller outputs match retained early-inner exactly. Original physical tolerance 1e-10*(1+abs(reference)) and residual/energy/cone/rollback/exact invariants remain unchanged. Original coverage remains 63/70, with the strict translated case 68, two baseline-64 convergence rejects and four old ledge cases without detachment still recorded. Separate boundary/ledge suites do not increase that numerator.

|Path / fixture|Early-inner API ms|Shared-table API ms|Median paired change|Verdict|
|---|---:|---:|---:|---|
|source / coupled sliding target|500.0060|474.9056|-5.160%|repeatable faster in bounded protocol|
|source / zero-friction floor|4.2333|4.5207|+3.678%|mixed/inconclusive|
|source / centered rebound|50.0188|47.1137|-6.950%|repeatable faster in bounded protocol|
|source / empty separated bodies|1.6503|1.7501|+3.521%|mixed/inconclusive|
|packaged / coupled sliding target|502.9989|477.5825|-4.849%|repeatable faster in bounded protocol|
|packaged / zero-friction floor|4.2457|4.2441|+1.779%|mixed/inconclusive|
|packaged / centered rebound|49.9982|47.0553|-6.100%|repeatable faster in bounded protocol|
|packaged / empty separated bodies|1.7354|1.6858|-0.377%|mixed/inconclusive|

Twelve warmed paired samples per mode/fixture/path, four batches, six balanced orders; first/warm-up exclusions fixed before timing. Faster/slower classification requires at least 10/12 signs and all four batch medians. No favorable reruns; this is bounded operational repeatability, not population confidence. Serial-tangent results, ranges, cold/setup costs, work records and every paired delta are in measured-performance.json.

|Fixture|Early-inner GPU solve ms|Shared-table GPU solve ms|
|---|---:|---:|
|coupled sliding target|488.7996|463.5828|
|zero-friction floor|0.1486|0.1410|
|centered rebound|43.5540|40.4992|
|empty separated bodies|0.0150|0.0150|

GPU durations use permitted Nsight Systems CUDA/NVTX activity correlation, seven warmed samples per owner/fixture. Source/package interleaving used 480 calls (288 measured); same-binary plain/traced profiles used another 240 calls. All 720 canonical records passed physical/exact gates, with candidate work/numeric equality to early-inner. One difficult-fixture call is one 1/30 s physical step: 96 outer sweeps, 429 linear solves, 2,102 residual evaluations, 1,315 line-search trials, nine fallback uses.

Launch/API, copy directions/bytes, synchronization waits, solver/packing/projection/validation GPU phases, register/local-memory metadata, traced/plain observations and sampled host/device memory are retained. Synchronization waits overlap device work and are not additive overhead. Register/local-memory declarations are metadata, not dynamic spill/stall measurements; those remain unmeasured and ERR_NVGPUCTRPERM was not retried. No broader-scene or PhysX claim.

Preservation: 8528 protected hashes, all 5,901 asset/save size/mtime identities, 17 campaign source hashes, 119 other source/lock hashes, and Mojo 1.2.0.dev2026092905 / isolated MAX 26.7.0.dev2026092905 verified unchanged. Minimum sampled available memory 110.701 GiB, above the 32 GiB reserve. Single execution slot, single-thread builds, finite 180/30 s guards. GPU idle and no owned jobs at seal; H3 was not resumed. No installs or hardware/security/profiling-permission changes.

[Compression assessment](COMPRESSION.md) explains dimensions, units, structural zeros, blocks, stored-bit symmetry and possible live packing without implementing compression. [Next warm-start design](WARM_START_DESIGN.md) specifies tangent-root cache quantities, actual identity/anchor/revision gaps, validation, invalidation, basis transport, no double application, cold fallback and transaction publication. It requires genuine consecutive-trajectory qualification and stops before implementation.

Evidence: verification.json, correctness-barrier.json, layout-proof.json, operator-structure.json, measured-performance.json, per-stage telemetry/build/trace/output records and FINAL-SHA256SUMS. Saved successful native stages were not repeated.
