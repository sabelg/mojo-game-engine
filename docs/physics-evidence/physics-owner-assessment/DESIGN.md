# Predeclared bounded three-owner interleaved comparison

Assessment only; no algorithm, default, policy or owner source changes. Reuse
existing qualified profiling fixture definitions and unchanged numerical gates.
Owners:O original GpuCoupledBoxResponse,I NT/TT-invariant cache,T tangent cache.
Fixtures:0 difficult3-body8-point coupled slide at30Hz/mu.2;1 centered box/floor
zero-friction normal response;2 centered2-body rebound withmu.2 but no transverse
slip/Newton work;3 empty separated static2-body at60Hz. No new positive-friction
material sweep is qualified or inferred; simple/low-friction control here ismu0.

True call-level interleaving inside one process per fixture/batch. All3owners
persist with their own identical initial inputs and device contexts. Same ordinary
BodyCommand reset outside each timed call. Four independent process batches per
fixture, each30s guard. Each owner/batch:1 first call and1 furtherwarmup discarded,
then3 warmed samples. Total12 warmed samples per owner/fixture,180calls total
(144warmed+36first/warmup). Constructors/context/uploads andCPU/analytic/golden
checks are outside timed integration+resolve wall. Diagnostic readbacks and
invalid-config byte rollback outside timing after everycall; no added in-API sync.
No profiler overhead in measured calls; existing GPU traces remain phase evidence.

Batch0/2 measuredcycle orders:OIT,ITO,TOI. Batch1/3 orders:OTI,TIO,IOT. Thus each
of six permutations is repeatedtwice; every owner appears fourtimes in each
ordinalposition,12 observations total. Cold/warmup owner order rotates bybatch.
Every invocation is recorded withbatch/cycle/position/owner. Newprocess cold/setup
costs reported separately and never included in warmed medians. No p95 claim.

Compare canonical states/impulses/histories/reports/work after everycall with saved
qualified baseline andindependentCPU/analytic/cone/energy/depth/profile/rollback
assertions. Unchanged solver/timestep/precision/budgets; no newcache warm start.
Same workload owner pairs usewithin-cycle differences,median/range/absolute ms
andpercent,perbatch median signs andbalanced position distributions. A regression
is termedrepeatable within this limitedprotocol only if>=10/12 paired differences
share that sign AND allfourbatch medians share it. Otherwise report variance/
inconclusive; threshold does not imply statistical confidence orgeneral crossover.
Record exactdelta/ranges regardless. No newheurstic/dispatch/policy code.

Read source for preexisting host coefficient and device postpack pair/point/
status metadata that might choose a path without added host mapping/sync. Counts
alone do notpredictNewton/disk work orprovea threshold. If no reliable crossover
across representative workloads is established,retain explicit user-selected modes.
Further serial micro gains vs a separatelyqualified cooperativeGPU design are
assessed from existingmeasuredkernel phases,notrender/broadphase speculation.

One-thread180s builds;30s eachbatch;32GiBavailable reserve;exclusive native/GPUslot,
H3paused. Preserve pinnedMojo/MAX,all priorcode/receipts/knownfailures,SDK/campaign/
assets/saves/dirtywork/locks/normalsettings. No installs,OS/driver/firmware orclock
changes,retiredthermal cutoffs,new features orpublication. Stopwithcleanup/evidence.
