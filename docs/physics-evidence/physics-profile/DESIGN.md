# Bounded qualified-physics timing baseline

No physics source, numerical policy, precision, timestep, iterations, kernel
launch configuration, synchronization/readback policy or API change. All harness
markers are standalone and opt-in. ExistingNsight Systems2025.3.2 traces CUDA/NVTX
with CPU sampling/context switches off, no settings changes or new dependencies.
GPU phase timing uses recorded CUDA activities and production kernel names;
synchronization API duration includes waiting and overlaps kernel time.

Four small qualified fixtures: original3-body8-point sliding target at30Hz,
mu.2/e0/96 velocity64 position sweeps; same original scene withmu0; centered
2-body4-point impact (mass2, half.5, initialoverlap1e-5, v±.5, mu.2/e.5,
zero gravity60Hz); separated static2-body no-contact case. Response entries are
reset through existing generation-checkedBodyCommand.update before every sample;
no warm-start/solver state reuse affects the cold solver numerical policy.

Per fixture and path: one first-call cold sample, two excluded warmups, seven
warmed independent resets. One process per fixture, same owner/buffers for all
samples. Setup/context creation+uploads, first step/response, and warmed calls
have separate host monotonic scopes. Diagnostic snapshots/counters and independent
CPU/physical assertions are excluded from step+response wall. Existing API status
readbacks remain included. Before instrumentation run the identical harness normally;
then source/CUDA-NVTX traced runs; lastly normal runs against a fresh precompiled
API. Compare all canonical raw states/impulses/history/counters across paths and
before/after instrumentation. Seven samples support median/range, no p95 claim.

Count actual outer sweeps, Newton corrections, residual evaluations, halving
trials, fallback attempts and rank counters using existing work_report. Report
integration, geometry/pairs, projection/packing, velocity response and validation/
commit GPU costs; host launch/synchronization/memory API scopes separately. No
rendering timing is used. Extra runtime/Python profiler overhead is disclosed.
No memory-usage tracing on timed runs; retain static buffer inventory, host peak
RSS and device process footprint where reported. Device instrumentation failure
must remain a concrete limit, never relabeled as kernel time.

All23 fields compared with independentCPU replay at original1e-10*(1+abs(reference));
analytic target/impact response, unchanged residual/Coulomb/energy/depth/profile,
fixed/accumulator/no-contact byte and invalid-configuration rollback gates pass
for everysample. Preserve original63/70, strict translated failure, baseline64
rejects and separate12/12ledge events. Exclusive native/GPUslot; H3paused; one-thread
180s compile,30s run and32GiBreserve. Pins unchanged. Finite profiling only;
stop with measured dominant cost, limitations and ranked gated recommendations.
