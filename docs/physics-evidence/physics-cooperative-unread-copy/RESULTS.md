# Copy-only cooperative solver checkpoint

Only277unread Float64 and16unread Int32shared input stores per evaluator call were removed. Arithmetic, private leader inputs, all offsets,4176bytes shared storage,144bytes owner diagnostics, barriers,108word output clearing, canaries, debug counters, work and commit remain unchanged. The retained cooperative owner and GpuCompactCooperativeBoxResponse are explicit opt-in modes.

The source read-set proof covers success, rejection, early return and inactive point paths under the original count0..4contract. All removed fields were poisoned and remained unchanged in9792actual-GPU controller records across source/fresh package and cooperative/leader controls. Full qualifications:280original-matrix trajectories,12target basis records,rank/validation/cache checks,160complete clock-disabled owner records,186regressions and720timed records match the retained references exactly. Original coverage remains63/70, including strictSAME-TIME case68failure, two baseline64convergence rejects and four oldledge non-detach cases. Independent75/75boundary and12/12ledge event passes are separate.

| Path / fixture | Retained cooperative API ms | Copy-only API ms | Paired change | Fixed protocol verdict |
|---|---:|---:|---:|---|
| source / coupled sliding target | 734.4965 | 620.4583 | -15.423% | repeatable faster in bounded protocol |
| source / zero-friction floor | 4.2605 | 4.7536 | +9.295% | mixed/inconclusive |
| source / centered rebound | 57.3027 | 51.4934 | -11.608% | repeatable faster in bounded protocol |
| source / empty separated bodies | 1.7630 | 1.7506 | +0.272% | mixed/inconclusive |
| packaged / coupled sliding target | 744.2060 | 632.5923 | -14.979% | repeatable faster in bounded protocol |
| packaged / zero-friction floor | 4.3859 | 5.3184 | +9.150% | repeatable slower in bounded protocol |
| packaged / centered rebound | 59.8983 | 51.2685 | -14.191% | repeatable faster in bounded protocol |
| packaged / empty separated bodies | 1.7765 | 1.7612 | +0.192% | mixed/inconclusive |

API is the original integration-plus-response host wall, with all original waits/readbacks. Twelve warmed paired samples per mode/fixture/path across four batches and six balanced orders; cold and warm-up calls excluded. The operational verdict requires at least10/12consistent signs and all four batch medians in the same direction. It is not a statistical confidence claim.

| Fixture | Retained cooperative GPU solve ms | Copy-only GPU solve ms | Serial tangent-cache GPU solve ms |
|---|---:|---:|---:|
| coupled sliding target | 728.9992 | 608.7009 | 1098.7615 |
| zero-friction floor | 0.1479 | 0.1407 | 0.1481 |
| centered rebound | 52.9552 | 45.2022 | 39.6841 |
| empty separated bodies | 0.0150 | 0.0153 | 0.0148 |

GPU values are device activity durations from seven warmed Nsight Systems samples, with CUDA correlation IDs checked against unchanged enqueue order. Synchronization waits overlap GPU execution and are not additive. Plain/traced runs use the same binary; observed differences include variance, not isolated clock, marker, barrier or debug overhead. Existing local-memory metadata and PTX declarations are not measured spill traffic.

Explicit storage increment versus retained cooperative:zero bytes. Sampled device/host RSS observations (not peaks or attributable allocation deltas):

- serial: device929MiB; hostRSS2991992KiB.
- baseline: device1047MiB; hostRSS3112384KiB.
- candidate: device1037MiB; hostRSS3102320KiB.

Nominal omitted store bytes are6,171,960per target solve and437,760per rebound solve. These are source-level logical stores, not measured bus traffic, and do not predict the runtime effect. No math, precision, solver gate, policy, warm start, substep or default changed; no broader performance/PhysX claim. The separate convergence diagnostic starts only after this checkpoint is reported.

All3019protected prior hashes,5901asset/save identities,17campaign sources,119other source/lock hashes and the pinned Mojo/MAX versions were verified unchanged. Minimum sampled available memory:110.64GiB;32GiBreserve retained. One-thread code generation,180scompile and30snative guards; GPU idle and no owned jobs at seal. H3 remains paused; no installations or system setting changes.

Evidence:verification.json,correctness-barrier.json,no-read-proof.json,math-exact.diff,full-solver-generated-behavior.json,measured-performance.json,per-run telemetry,complete traces and FINAL-SHA256SUMS.
