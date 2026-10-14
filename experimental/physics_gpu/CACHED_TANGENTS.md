# Bounded opt-in original tangent-basis/local-metric reuse

`experimental.physics_gpu.cached_tangent_response.GpuCachedTangentBoxResponse`
is a separate opt-in path extending the retainedNT/TT-only
`GpuCachedCoupledBoxResponse`. Original unoptimized andNT/TT-only code/executables
remain available. No default/recommended Atlas API or SDK change.

The new path caches the exact original`tangent_axes` result per selected patch
and the exact original`tangent_metric` result per selected point, using those
unchanged functions. It never substitutes TT diagonals, reuses factorization or
adds Jacobian tables. Existing Newton/disk64-bisection/halving, precision, law,
timestep, sweep ordering, convergence/slop/rollback policies are unchanged.

Mass/inertia, postprojection COM/orientation, reconstructed selected points/
normals and tangent-basis parameters stay fixed while velocity/impulses change.
Every positive-friction resolve clears allpayload and rebuildsNT/TT,bases and
localmetrics after projection andfresh bounds/SAT/reduction/constraint packing.
No previousgeometry/pose/material/basis/revision/generation is trusted. mu0 uses
originalnormal response andconsumes no tangent cache. Contiguous packed spans
identify the basis for each residual point in the original point order.

The privatebuffer is1826Float64 words (14608bytes):1536NT/TT +96basis +192metric
words +two canaries. This adds2304bytes versus theNT/TT-only buffer andno new
buffer/launch. The existing serial cache-pack andvelocity launch geometry stays
oneblock/one thread. Inactive slots/pads are zeroed everypack; canaries remain.

Source/fresh-precompiled all70 original trajectory inputs/results/fulltraces
are byte-identical (140cases), retaining63/70full coverage andknown failures.
All320 priorprofiling records are explicitly matched;80clock-disabled candidate
samples and240new pairedtimed samples produce320new identicalcanonical records.
No non-bitwise state/impulse/history/report/work difference was accepted.

The0/45/90 targets,seed61rank3/permutation/conditioning,Jacobian,nonfinite/configuration,
physical residual/Coulomb/energy/depth/profile andexact body/metadata rollback
checks pass. Twenty cache proofs compare original per-point basis/metric
reassembly after solving to everycached value,padding/canary,including all8points
of the qualifiedtwo-patch target. They exercise bodypose/localorientation/shape
resize/revision,basis/material changes,contactloss/mu0,generation reuse and
stale/foreign/immutable-mass error15 rollback. Fields0..10 are fixed through
velocity solving. Original320sample and70case evidence remain preserved.

Pairedfinite timing uses onefirstcall,twoexcludedwarmups,seven warmed independent
resets perfixture/variant/path. AgainstNT/TT-only caching,the coupled target
source median step+response is1145.786→1101.804ms (observed3.84%lower; ranges
1142.181–1154.691 versus1097.370–1109.448ms),precompiled1150.263→1115.837ms
(2.99%lower; ranges1146.730–1156.158 versus1109.719–1125.096ms).
TracedGPU solver median1123.708→1090.371ms;packing2.160→2.455ms. Work remains
96sweeps,192attempts,505Newton/linear solves,2707residual evaluations,1853halving
trials and0fallbacks;actualposition sweeps23/budget64.

Centeredrebound source medians74.783→45.650ms (38.96%lower),with96attempts/
192evaluations/0Newton unchanged. Cheapcontrols are mixed:normal source median
4.163→4.346ms;empty-contact precompiled1.767→1.949ms (+10.3%median inthisrun,
withoverlapping ranges1.654–3.090 and1.681–2.468ms). There isno blanket cheap-control
benefit. Allsource/precompiled/CUDA-NVTX phase/cold/compile/readback ranges and
packing/memory overhead are documented. Source-scheduled basis962→2/metric768→8
reductions are not runtime-speedup claims. Finite7-sample medians do not establish
p95,populationgain,broad scenes,stable stacks,real-time orPhysX parity.

InitialPython generator parse error occurred before sourcegeneration/native
execution;the corrected generator anddiagnostic are retained. There were no
native fixture failures orrelaxed gates. AllbaselineSDK/campaign/assets/saves/
pins/locks/dirtywork/settings stay;H3paused;no installs,broaderparallelism,
OS/driver/firmware changes orpublication. Originalstricttranslatedcase68failure,
two baseline64 rejects andfouroldledgegaps remain,separate from12/12ledge and
75/75translation suites. Stop at thisone boundedoptimization.

Evidence:`build/physics-tangent-reuse/{INVARIANTS.md,correctness-comparison.json,
RESULTS.md,measured-AB.json,verification.json,SHA256SUMS}`,complete source/precompiled
70case traces,target/rank/validation/cache logs,A/Bharnesses/executables,freshAPI,
CUDA-NVTX`.nsys-rep`/SQLite captures andGPU-phaseJSONs.
