# Bounded tangent-basis/local-metric cache: exact A/B and measured timing

A separate opt-in GpuCachedTangentBoxResponse extends the retainedNT/TT-only GpuCachedCoupledBoxResponse. Only the original tangent_axes results per patch and original tangent_metric results per selected point are cached. Original unoptimized andNT/TT-only code/executables/receipts stay available.

## Exact numerical qualification

Source/fresh-precompiled original70-case inputs/results/complete trajectories are byte-identical (140cases); full coverage stays63/70 with strict translated case68, two baseline64 rejects and four old ledge gaps retained. The0/45/90targets, seed61rank3/permutation/conditioning/Jacobian checks, nonfinite/configuration/Coulomb/energy/profile andbody/metadata rollback gates pass. Twenty cache proofs include per-point basis/metric original-function reassembly for all8points of the qualifiedtwo-patch target, as well as9mutationcases per path. They verify postprojection mass/inertia/COM/orientation fields0..10 unchanged, canaries/padding, basis/shape/body pose/local orientation/revision/generation/material/contact-loss/mu0 behavior, and immutable-mass error15/stale/foreign rollback.

Before timing,80 clock-disabled candidate samples were compared against every record of the previous320-sample dataset explicitly. After that correctness barrier,240 new pairedtimed samples (two variants×source/CUDA-NVTX/precompiled×fourfixtures×ten samples) match all original canonical raw states, impulses, residual histories, reports, energy andwork counters. This checkpoint has320 new canonical records with no accepted non-bitwise difference.

The cache is rebuilt within the existing serial packing launch after projection andfresh bounds/SAT/contact reconstruction. Every positive-mu resolve clears all1824payload words and repacksNT/TT,bases andlocalmetrics. It trusts no priorcall/revision/generation/shape/pose/basis/material. mu0 does not consume the cache. Velocity/free terms, pressure/mask/radius,disk root,Jacobian,rank factorization andfirst-accepted line search remain dynamic. No factors orJacobian tables were cached. Terminal point-to-patch lookup follows the original contiguous spans andpoint order. Original tangent_metric is called exactly; TT diagonals are not substituted.

## Finite paired warmed A/B

Baseline below means currentNT/TT-only cache; candidate means additionalbasis/localmetrics. Everyfixture/variant/path has one first call,two excludedwarmups andseven warmed independently reset samples. Compile/context/uploads/cold costs are separate. CPU/analytic checks, resetcommands,snapshots/history/counters andJSON are outside step+response timing; existing API status/readbacks andwaits stay inside. No clock/cache/settings reset was forced. Median/observedrange only; no p95 or population speedup claim.

|Workload|SourceNT/TT-only ms median [range]|Sourceextended ms median [range]|Observed source median reduction|PrecompiledNT/TT-only→extended ms medians|GPU kernel sumNT/TT-only→extended ms medians|
|---|---|---|---|---|---|
|coupled sliding target|1145.786 [1142.181–1154.691]|1101.804 [1097.370–1109.448]|3.84%|1150.263→1115.837|1135.677→1103.638|
|centered box/floor normal|4.163 [4.129–5.394]|4.346 [4.161–6.314]|-4.39%|4.868→4.746|4.239→4.117|
|centered two-body rebound|74.783 [74.013–75.289]|45.650 [45.288–47.676]|38.96%|74.982→48.077|74.354→45.657|
|separated no-contact|1.681 [1.645–2.648]|1.676 [1.644–1.759]|0.29%|1.767→1.949|1.551→1.563|

coupled sliding target: observed warmed median changes are3.84% source,2.82% traced API,2.99% precompiled. Positive means lower candidate median; negative means higher. These are finite observations, not statistical estimates for other scenes. All ranges and cold costs are below.

centered box/floor normal: observed warmed median changes are-4.39% source,2.70% traced API,2.51% precompiled. Positive means lower candidate median; negative means higher. These are finite observations, not statistical estimates for other scenes. All ranges and cold costs are below.

centered two-body rebound: observed warmed median changes are38.96% source,38.51% traced API,35.88% precompiled. Positive means lower candidate median; negative means higher. These are finite observations, not statistical estimates for other scenes. All ranges and cold costs are below.

separated no-contact: observed warmed median changes are0.29% source,0.19% traced API,-10.30% precompiled. Positive means lower candidate median; negative means higher. These are finite observations, not statistical estimates for other scenes. All ranges and cold costs are below.

A reduction in source-scheduled evaluations is not a runtime speedup. On the target,basis calls in velocity+packing drop962→2 andoriginal local metric evaluations in terminal checks768→8; these are counts derived from the unchanged96-sweep/8-point schedule and192 attempts. Actual measured API/GPU changes above are the performance result. Cheap controlranges must be assessed separately; no blanket benefit follows.

## GPU packing/solver andwork costs

|Variant/workload|Actual velocity/position sweeps|Attempts/Newton/residual evaluations|GPU solver ms median [range]|GPU packing ms median [range]|Launches/waitAPIs|
|---|---|---|---|---|---|
|baseline/coupled sliding target|96/23|192/505/2707|1123.708096 [1118.190912–1135.602496]|2.160032 [1.972896–2.604096]|[18]/[25]|
|cached/coupled sliding target|96/23|192/505/2707|1090.370880 [1087.743616–1096.527008]|2.455328 [2.266944–3.080000]|[18]/[25]|
|baseline/centered box/floor normal|1/1|0/0/0|0.147392 [0.139744–0.151104]|none|[17]/[25]|
|cached/centered box/floor normal|1/1|0/0/0|0.147552 [0.139616–0.153184]|none|[17]/[25]|
|baseline/centered two-body rebound|96/1|96/0/192|68.649952 [67.115840–71.095232]|1.302208 [1.300576–1.932352]|[18]/[25]|
|cached/centered two-body rebound|96/1|96/0/192|39.886976 [39.213536–42.218816]|1.489952 [1.489024–1.872544]|[18]/[25]|
|baseline/separated no-contact|0/1|0/0/0|0.014912 [0.014848–0.015936]|0.003456 [0.003424–0.003488]|[18]/[25]|
|cached/separated no-contact|0/1|0/0/0|0.015776 [0.014688–0.024256]|0.003936 [0.003904–0.004448]|[18]/[25]|

Target remains96velocity/23actual position sweeps,192 attempts/accepted,0fallbacks,505 Newton/linear solves,2707 residual evaluations,1853halving evaluations,rank sum4016/max8 and0profile rejects. Position budget64,local8Newton/16halving anddisk64bisection policies remain. No added trials or altered stopping law. The centered impact also retains96attempts/192residual evaluations/0Newton.

|Target traced phase ms median|NT/TT-only|Extended|
|---|---|---|
|integration_GPU_ms|0.191808|0.191648|
|registry_reconciliation_GPU_ms|0.085408|0.085440|
|geometry_pairs_GPU_ms|0.478016|0.477056|
|position_projection_GPU_ms|4.163776|4.370240|
|constraint_packing_GPU_ms|4.440320|4.277664|
|invariant_cache_pack_GPU_ms|2.160032|2.455328|
|velocity_response_GPU_ms|1123.708096|1090.370880|
|validation_commit_GPU_ms|0.208640|0.208608|
|launch_API_ms|0.037936|0.038656|
|synchronization_wait_API_ms|1135.740304|1103.699728|
|memory_copy_API_ms|0.031088|0.030640|
|unattributed_host_minus_kernel_ms|0.199296|0.180976|

GPU activities are assigned by CUDA correlation IDs within NVTX host scopes. Positive-mu remains18kernel launches (integration3,response15),mu0 remains17. Packing andvelocity kernels retain grid1/block1; no parallel execution change. Existingwait APIs remain25 andlogical API copy payload9,376bytes each way; external diagnostic copies50,816bytes each way remain excluded. Synchronization durations include device waits andoverlap kernels, so they are not additive overhead. Medians of phase rows do not necessarily add to median total. No instruction/spill attribution,render timing/broadphase inference orPhysX claim is made.

## Compile/context/cold/readback separation

|Variant/path/fixture|Context/setup/uploads ms|First step+response ms|Warmed API ms median [range]|Diagnostic readback ms median [range]|
|---|---|---|---|---|
|baseline/plain/0|807.891|1151.519|1145.786 [1142.181–1154.691]|0.135 [0.124–0.305]|
|baseline/trace/0|780.360|1154.826|1135.859 [1130.475–1147.339]|0.159 [0.128–0.181]|
|baseline/packaged/0|794.820|1158.464|1150.263 [1146.730–1156.158]|0.107 [0.104–0.118]|
|cached/plain/0|798.669|1118.941|1101.804 [1097.370–1109.448]|0.125 [0.124–0.135]|
|cached/trace/0|824.592|1113.453|1103.823 [1099.771–1110.007]|0.154 [0.134–0.167]|
|cached/packaged/0|789.614|1117.168|1115.837 [1109.719–1125.096]|0.123 [0.104–0.125]|
|baseline/plain/1|761.128|12.416|4.163 [4.129–5.394]|0.108 [0.090–0.119]|
|baseline/trace/1|791.806|11.687|4.400 [4.179–5.326]|0.141 [0.121–0.152]|
|baseline/packaged/1|762.700|12.294|4.868 [4.132–6.130]|0.113 [0.091–0.342]|
|cached/plain/1|763.141|12.591|4.346 [4.161–6.314]|0.115 [0.102–0.126]|
|cached/trace/1|791.260|13.361|4.281 [4.168–6.297]|0.143 [0.138–0.401]|
|cached/packaged/1|765.420|12.450|4.746 [4.104–5.317]|0.110 [0.092–0.277]|
|baseline/plain/2|761.388|90.741|74.783 [74.013–75.289]|0.120 [0.102–0.126]|
|baseline/trace/2|800.582|92.278|74.546 [72.674–77.464]|0.154 [0.149–0.165]|
|baseline/packaged/2|755.341|91.723|74.982 [73.087–78.519]|0.099 [0.090–0.119]|
|cached/plain/2|753.956|66.116|45.650 [45.288–47.676]|0.120 [0.099–0.139]|
|cached/trace/2|830.993|60.965|45.840 [44.995–47.950]|0.147 [0.127–0.349]|
|cached/packaged/2|757.430|64.426|48.077 [45.090–49.284]|0.112 [0.098–0.433]|
|baseline/plain/3|744.086|16.600|1.681 [1.645–2.648]|0.108 [0.084–0.110]|
|baseline/trace/3|783.144|16.510|1.717 [1.674–1.978]|0.139 [0.119–0.142]|
|baseline/packaged/3|750.699|18.926|1.767 [1.654–3.090]|0.104 [0.090–0.112]|
|cached/plain/3|770.875|19.894|1.676 [1.644–1.759]|0.109 [0.090–0.111]|
|cached/trace/3|837.668|22.044|1.714 [1.681–3.383]|0.123 [0.118–0.162]|
|cached/packaged/3|749.867|15.804|1.949 [1.681–2.468]|0.113 [0.098–0.370]|

Firstcall uses a newowner/context with existingdisk/MAX/driver caches; it is not a forced-empty-cache measure. Warmed windows have no module-load APIs. Compilation andNsight export are excluded.

|Build stage|Guarded host wall s|
|---|---|
|package-precompile|5.250|
|baseline-timed-source-compile|14.254|
|cached-timed-source-compile|14.741|
|baseline-timed-packaged-compile|15.855|
|cached-timed-packaged-compile|16.396|

## Memory andscope

Cache buffer grows1538→1826Float64 words:12,304→14,608bytes,exactly2304extra payloadbytes,no additionalbuffer orkernel launch. Layout is1536NT/TT +96basis +192pointmetric words +2canaries. Explicit steady targetdevice storage grows3.497227→3.499424MiB;constructor buffers remain67. The mu0 control still allocates storage but does not pack/read it.

Maximum sampled process footprint:NT/TT-only929MiB device/2921.9MiB RSS;extended929MiB device/2921.8MiB RSS. These include context/code/runtime/profiler pools andcaches,roughly.5s sampling plusobserver overhead,and are not guaranteed peaks or attributable buffer savings. Exact2304B is the storage change.32GiBreserve remains;CPU/context-switch/memory-usage tracing disabled.

This result is the bounded thirdopt-in path only. Original andNT/TT-only paths,all baseline code/receipts/failed fixtures remain. Original fullcoverage63/70 andseparate12/12ledge/75/75translation qualifications stay distinct. No factorreuse,Jacobian tables,new features,broaderparallelism,precision/timestep/iteration changes,dependencies,OS/driver/firmware/settings changes orpublication. H3stays paused. No generalstack,tail-latency,real-time orPhysX-parity extrapolation.

Evidence:INVARIANTS.md,correctness-comparison.json,measured-AB.json,source/precompiled70case traces,target/rank/validation/cache proofs,A/Bsample/cold/telemetry records,standaloneexecutables/freshAPI andNsightCUDA-NVTXcaptures,GPU-phaseJSONs,finalverification.json/SHA256SUMS. InitialPython generator parse error occurred before source creation; no numerical fixture failure orrelaxed gate resulted.
