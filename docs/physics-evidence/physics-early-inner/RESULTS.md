# Early-inner stopping experiment

Separate opt-in candidate; only the additional first-eight-sweep 1 percent root stop was added. All 96 outer sweeps,8 Newton/16 trial caps, fixed 64 disk bisection, pivots, fallback, final evaluation and final physical/residual/cone/energy/rollback gates remain unchanged. No other optimization, automatic dispatch or default replacement.

First difficult fixture passed with independent CPU physical-state ratio 0.0019780644 and retained-reference ratio 0.0004580662; maximum raw-body difference 5.65936e-14. First-record work changed from[192,192,0,505,2707,505,1853,4016,8,0]to[192,183,9,429,2102,429,1315,3405,8,0], retaining all 96 sweeps. Nine preserved fallback uses are explicit.

Correctness:140 source/fresh-package original trajectories under unchanged 1e-10*(1+abs_reference_field),6 basis checks,rank/derivative/rejection checks,source/package cache/lifecycle/rollback,9792 bit-exact controller records,186 regressions and 80 clock-disabled complete-owner records. Discrete/static/immutable/inactive/canary/rollback invariants remain exact; mathematical work, residual-history and permissible dynamic-state differences are retained. Maximum matrix reference-state ratio:0.021874476177113862. Original 63/70 accounting and all known failures remain unchanged.

|Path / fixture|Copy-only API ms|Early-inner API ms|Paired change|Verdict|
|---|---:|---:|---:|---|
|source/coupled sliding target|627.5534|516.6341|-17.747%|repeatable faster in bounded protocol|
|source/zero-friction floor|4.3474|4.2461|-1.428%|mixed/inconclusive|
|source/centered rebound|51.1611|50.9737|+1.273%|mixed/inconclusive|
|source/empty separated bodies|1.7538|1.7637|-0.151%|mixed/inconclusive|
|packaged/coupled sliding target|631.4941|519.3814|-17.788%|repeatable faster in bounded protocol|
|packaged/zero-friction floor|4.9665|4.8306|-0.067%|mixed/inconclusive|
|packaged/centered rebound|52.0342|51.8457|+0.134%|mixed/inconclusive|
|packaged/empty separated bodies|1.7691|1.7678|-3.457%|mixed/inconclusive|

Twelve warmed paired samples per mode/fixture/path, four batches, six balanced orders; cold/warm-up exclusions frozen before timing. Operational repeatability>=10/12 signs and all four batch medians, not population confidence. No repeated runs for favorable results.

|Fixture|Copy-only GPU solve ms|Early-inner GPU solve ms|
|---|---:|---:|
|coupled sliding target|606.8646|501.9810|
|zero-friction floor|0.1399|0.1481|
|centered rebound|44.9156|45.2928|
|empty separated bodies|0.0150|0.0150|

GPU durations use existing CUDA/NVTX activity correlation,7 warmed samples. Main interleaved timing has no added convergence tracing; production work/canary counters remain enabled. Plain/traced profiles reuse identical binaries; tracer differences include variance. Synchronization waits overlap GPU work, not additive. Each target call represents one 1/30 second physical step, not 96 physical steps. Actual per-mode operation records, memory observations, samples/ranges and cold/setup times are in measured-performance.json. No PhysX/general performance claim or dynamic spill attribution.

All 6176 prior hashes,5901 asset/save identities,17 campaign sources,119 other hashes and pins verified unchanged. Minimum available memory:111.0145034790039 GiB. GPU idle, no owned jobs, H 3 paused; no installs/settings changes. Initial harness frontend error and reject-schema parser error retained; no successful native test rerun. Stop at this verified checkpoint.

Evidence:verification.json,correctness-barrier.json,first-target-comparison.json,candidate.diff,complete trajectories/controller outputs,per-stage logs/telemetry,build receipts,measured-performance.json and FINAL-SHA 256 SUMS.
