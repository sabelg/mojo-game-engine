# Cooperative DP component assembly

One isolated candidate distributes the 21 independent component sums within each suffix RK stage. Each component retains original k-order arithmetic; lane 0 retains ordered publication, first-failure tube admission, RHS evaluation and counts. A barrier publishes each stage slope before the next stage. Final combination is also component-independent with unchanged k order. The full/two-half paths, prefix integrator, contact refresh, error estimation, work caps and adaptive decisions remain unchanged.

**332 original bitwise records**, **224 macro reject/recover records**, **640 enclosure lifecycle comparisons**, **224 independent Decimal100 supersolution checks**, and **16 forced enclosure rejection/recovery comparisons** pass. Added direct DP tests pass **80 differential helper comparisons (40 rejected, 40 recovered)** across eight native launches, checking codes and 211 partial destination/temp/slope/maxima/count words each. Failures include stage-0 tube gates at components 0/10/20, later-stage tube admission, and RHS rejection. Counts verify no skipped or extra RHS. Source/package identity covers 45 modules. All 1,188 main timing/diagnostic calls and ten preflight calls validate original receipts.

All-case API medians: **40.607–42.926 ms**. Fresh paired API speedup **1.067–1.100×**, latency reduction **6.272–9.088%**, CUDA kernel speedup **1.004–1.128×**.

## Synchronization and scratch

The helper uses 15 block barriers per successful call, 720 across the 48 suffix calls, plus 16 additional wrapper barriers. Its 22 scratch words occupy [64500,64522) inside the unchanged 65536-word allocation. Extra component traffic is 147 writes and 147 reads per helper (2352 bytes), totaling 112896 bytes per full suffix, plus shared status accesses. No new allocation or kernel launch. Stage and end-to-end timings include all synchronization and traffic. The exact supported launch remains one 32x1x1 block; spare lanes participate in barriers. DERIVATION.md describes the dependency, arithmetic and uniform-return argument.

## Separate stage costs

| Stage | Baseline ms | Candidate ms |
|---|---:|---:|
| Event search/prefix gates | 5.309–5.620 | 5.272–5.624 |
| Prefix ODE | 7.915–7.924 | 7.832–7.924 |
| Suffix ODE including cooperation | 7.169–7.518 | 4.916–5.168 |
| Event transport | 6.112–6.363 | 6.262–6.464 |
| Suffix geometry/gates | 5.531–5.608 | 5.428–5.899 |
| Enclosure solves | 3.695–3.698 | 3.721–3.807 |
| Comparison matrix | 1.249–1.249 | 1.243–1.244 |
| Global tube/setup | 0.835–0.836 | 0.836–0.838 |
| Final accounting/commit | 2.148–2.150 | 2.091–2.143 |
| Other initialization/wrapper | 2.065–2.078 | 2.058–2.082 |
| Whole diagnostic kernel | 43.426–43.691 | 40.882–42.277 |

| Internal component | Baseline ms | Candidate ms |
|---|---:|---:|
| suffix_stage_assembly_ms | 3.633–3.639 | 1.457–1.465 |
| suffix_RHS_ms | 3.256–3.352 | 3.278–3.385 |
| suffix_final_combination_ms | 0.224–0.225 | 0.011–0.011 |
| local_shape_interval_ms | 2.172–2.174 | 2.173–2.174 |
| fresh_body_rotation_ms | 2.672–2.673 | 2.676–2.932 |

Candidate assembly timing includes publication, tube admission and the first barrier; RHS timing includes the second barrier, and final combination includes its completion barrier. Timing instrumentation may affect generated code. End-to-end gains use uninstrumented API runs and launch-correlated CUDA activity. Geometry counts remain 144 local evaluations, 144 world rotations and 18 checks in both variants.

## Full-macro medians and tails

| Case/path | API median / p95 / max ms | Historical median speedup |
|---|---:|---:|
| 0 / source | 41.394 / 43.738 / 44.185 | 1.050× |
| 1 / source | 41.329 / 43.707 / 44.629 | 1.049× |
| 2 / source | 40.825 / 42.211 / 42.352 | 1.066× |
| 3 / source | 40.607 / 42.119 / 43.322 | 1.088× |
| 4 / source | 40.916 / 42.676 / 43.116 | 1.059× |
| 5 / source | 40.849 / 42.270 / 42.582 | 1.071× |
| 6 / source | 42.926 / 43.813 / 44.003 | 1.033× |
| 7 / source | 40.671 / 42.828 / 43.915 | 1.065× |
| 8 / source | 41.436 / 43.540 / 44.346 | 1.059× |
| 0 / packaged | 41.161 / 43.545 / 43.742 | 1.055× |
| 1 / packaged | 42.056 / 43.516 / 43.763 | 1.052× |
| 2 / packaged | 41.036 / 42.032 / 42.600 | 1.068× |
| 3 / packaged | 40.630 / 42.844 / 43.809 | 1.070× |
| 4 / packaged | 42.051 / 44.248 / 44.631 | 1.055× |
| 5 / packaged | 40.796 / 42.425 / 43.175 | 1.069× |
| 6 / packaged | 40.698 / 41.836 / 41.984 | 1.079× |
| 7 / packaged | 40.889 / 42.703 / 43.441 | 1.061× |
| 8 / packaged | 40.758 / 42.160 / 42.305 | 1.082× |

| Fresh paired case/path | API speedup | GPU speedup |
|---|---:|---:|
| 0 / source | 1.067× | 1.076× |
| 3 / source | 1.100× | 1.062× |
| 7 / source | 1.085× | 1.050× |
| 0 / packaged | 1.070× | 1.004× |
| 3 / packaged | 1.087× | 1.128× |
| 7 / packaged | 1.082× | 1.016× |

The first direct DP coverage checker correctly rejected the initial probe campaign: zero-radius/equal-anchor cases reached stage 1 rather than stage 0. Final v2 probes use a finite anchor offset and retain the original strict RHS-count assertions. Initial sources, binaries, samples and failed checker are preserved. No production implementation or accuracy gate changed.

## Budget and regressions

The 33.333 ms budget is met by all case/path medians: **False**. Median gap: **7.274–9.593 ms**. Retained ordinary API samples over budget: **432/432**. Across every production timed call including warmups/preflight/traces: **706/706** exceed budget. Worst production observation: **50.779 ms**, trace-candidate-source-c3-b0-samples.jsonl, sample 0. CUDA observations over budget including warmups: **156/156**. Diagnostic and recovery timings are separately identified in step-budget-check.json; they are not production latency claims.

Current median/p95/max regression comparison records: **1**, retained in regressions.json with all prior history. Combined prefix+suffix ODE median changes (per-sample sums): case 0: -2.131 ms, case 3: -2.670 ms, case 7: -2.686 ms. No cause is inferred for changes to untouched stages.

Each retained distribution has n=24; p95/p99 and maxima describe this run, not guarantees. Cases 0/3/7 have fresh alternating paired runs; other cases use historical comparisons. Compilation, setup, reset and validation are separate from API time. GPU and synchronization durations overlap and are not added.

## Preservation and scope

All 5,908 protected hashes and 7,108 asset/save identities match. Mojo 1.2.0.dev2026092905 / MAX 26.7.0.dev2026092905 pins and HEAD unchanged. Minimum available memory 110.413 GiB; maximum GPU temperature 40 C. Single execution/GPU slot, single compiler thread and finite guards retained. No owned jobs or GPU compute processes remain; H3 paused. No publication, system/driver/power/security changes or denied counters.

Scope remains the same nine single-body, spherical-inertia, constant-force, zero-torque, frictionless/inelastic, single-switch 1/30-second entries. Independent analytic/high-precision evidence transfers through exact identity; empirical ODE assumptions remain. No trajectory, consecutive ownership, general multibody or real-time guarantee.

Evidence: verification.json, correctness-barrier.json, dp-recovery-check.json, rejection-recovery-check.json, lifecycle-independent-check.json, performance.json, geometry-attribution.json, regressions.json, step-budget-check.json, preservation-audit.json, DERIVATION.md, METHOD.md, SOURCE-CHANGE.diff and FINAL-SHA256SUMS.

CUDA tail detail, case 0 / packaged: p95 44.397 -> 44.732 ms; max 45.086 -> 45.108 ms. These samples are retained, and the median gain does not erase this tail regression.
