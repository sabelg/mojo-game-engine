# Bounded opt-in resolve-local coupled geometry reuse

`GpuCachedCoupledBoxResponse` is an isolated opt-in version of the existing
coupled response. It assembles the normal/tangentNT and tangent/tangentTT
cross-metric blocks once per selected patch after position projection and fresh
contact reconstruction, then reuses them across the unchanged velocity sweeps.
The original `GpuCoupledBoxResponse` and default/recommended Atlas APIs remain.

Mass/inertia, COM/orientation, selected contact points/normal and tangent basis
are invariant during velocity response. Velocity/impulses/pressure/active masks,
residuals, Jacobians, disk radii and Newton iterates are recomputed as before.
NT/TT were already reused inside an individual Newton attempt; this change removes
their repeated assembly across outer attempts. NN and normal-mask operators were
already cached and are unchanged. Fallback/residual tangent_metric operation
order is retained rather than replacing it with potentially differently rounded
TT diagonals. No law, precision, timestep, iteration/convergence/slop policy,
complete-pivot rank rule or broader parallelism changes.

The extra private buffer is1538Float64 words:16*(32NT+64TT), two canaries,
12,304bytes total. Every positive-friction resolve clears all payload words and
fills active blocks using its current projected/reconstructed geometry. No prior
resolve's values are trusted. Generation/revision, pose, local shape, basis or
material changes cannot reuse old geometry. Zero-friction uses the original
normal branch and never consumes this buffer. There is one additional serial
cache-pack launch for positive friction. Allocation persists with the owner;
cache validity is restricted to the current resolve.

Source and fresh precompiled actual-GPU qualification retain byte-identical
initial/result/full traces for all70 original cases per path, unchanged63/70 full
coverage, all three target tangent bases and the seed61rank3/permutation witness.
The320 profiling sample records (80 correctness-only,240timed A/B) have identical
raw body buffers, impulses, histories, reports and work counters versus the saved
baseline. There is no accepted non-bitwise numerical difference. Conditioning,
nonfinite/configuration/Coulomb/energy/profile/byte rollback gates pass.

Nine cache proofs per path compare direct old cross_metric reassembly from
post-solve bodies to all cached blocks/padding/canaries, and verify unchanged
mass/inertia/COM/orientation fields during velocity solving. They exercise basis,
pose, collider revision/resize/local orientation, material, no contacts, mu0,
stale/foreign handles and remove/recreate with new generations. The initial test
correctly hit existing error15 for a live-body mass/inertia-changing update; its
source/log/executable are retained. The corrected test verifies immutable-mass
rollback and changes mass through supported remove/recreate. No gate was changed.

Paired bounded timing uses one first call, two excluded warmups and seven warmed
independent resets per fixture/variant/path. Compile/context/setup/cold calls,
host API and GPU phases are separately recorded. On the original3-body8-point
sliding target, source median step+response is1350.252→1135.324ms (observed15.92%
reduction), precompiled1367.395→1152.824ms (15.69%). Traced solver median is
1341.901→1127.899ms; extra cache-pack is1.976ms. Solver work remains96 sweeps,
192 attempts,505 Newton corrections,2707 residual evaluations and0 fallbacks.

The centered2-body rebound observes211.668→75.606ms source medians, with96 attempts,
192 residual evaluations and0 Newton corrections unchanged. Cheap normal/no-contact
controls have mixed overlapping host ranges; no benefit is claimed for them.
The empty no-contact cache-pack adds about0.003ms GPU time. All sample ranges and
phase/memory limits are in the report. These finite measurements do not establish
p95, statistical population gains, broad scenes, general stacks, real-time or
PhysX parity. The expensive solver remains opt-in and serial.

Original strict translated collision failure, two baseline64 rejects and four
old one-second ledge gaps remain. Separate12/12ledge and75/75translation suites
remain distinct. Original sources/executables/coverage and failure evidence,
SDK/campaign/assets/saves/dirty work/pins/locks/settings are preserved. H3paused;
no dependencies or system/driver/firmware changes.

Evidence: `build/physics-invariant-reuse/{INVARIANTS.md,
MASS_LIFECYCLE_CLARIFICATION.md,correctness-comparison.json,RESULTS.md,
measured-AB.json,verification.json,SHA256SUMS}`, source/precompiled complete70-case
traces, target/rank/validation/cache outputs, standalone A/B samples/executables
and NsightSystems CUDA/NVTX `.nsys-rep`/SQLite captures. This checkpoint stops at
this one verified invariant-reuse optimization.
