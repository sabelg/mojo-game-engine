# Experimental cooperative box response

`GpuCooperativeBoxResponse` is a separate opt-in owner. It retains the existing
tangent-cache law/Float64/64-or96 policies and original validation/commit, while
one persistent32-lane block cooperates only on independent point residual and
Jacobian rows. Pressure/dP/mask order, complete pivots, reductions, line-search
first acceptance and body/patch/sweep feedback remain serial. All lanes follow
shared decisions and uniform barriers. `leader_only=True` is the explicit
research measurement control; original and cached owners/defaults stay intact.

The bounded exact source/fresh-package qualification preserves all original
70case traces/work decisions and original63/70failure accounting. It also covers
controller count0..4/partial invalids/inactive lanes/reuse, bases0/45/90, rank,
physical-state/energy/rollback and affected regressions. This is a finite pinned
GB10/toolchain contract, not exhaustive race proof or cross-device equivalence.

Measured difficult-target benefit accompanies a centered-rebound regression.
Keep explicit modes. No automatic selector, broad-scene, real-time, scalability
orPhysX-parity claim is supported. Debug/canary cost is included; never describe
host/API wall as GPU-only time. See
`build/physics-cooperative-integration/RESULTS.md`, `measured-performance.json`,
`BARRIER_AUDIT.md`, `correctness-barrier.json`, `verification.json` and
`FINAL-SHA256SUMS` for exact sample counts, ranges, limitations and fingerprints.
