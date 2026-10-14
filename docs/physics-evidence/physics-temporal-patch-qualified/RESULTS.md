# Temporal patch: corrected lifecycle qualification and measured tradeoff

Applied only the diagnosed lifecycle test oracle correction and added explicit no-restitution/fresh-identity assertions. Candidate owner/kernel arithmetic, Float64 precision, solver/budgets, physical gates, rollback and all other owners remain unchanged. The original failed receipt and every prior evidence file are intact; its original test source is saved as original-failed-lifecycle.mojo with matching SHA. The correction diff and authorized-source-change.json account for the one current test path changed from its historical manifest.

The local counter is now toi_admissions with a comment explaining zero-time cold discovery, rather than bounce impulses. The legacy JSON events field contains that same TOI counter. Detach/attach increments shape generation1→2 while revision resets1→1 and both body generations stay1. That new key makes saved touching ineligible. The existing negative roundoff velocity admits one t=0 root, below the-.2m/s restitution threshold. Corrected case7 expects one admission and asserts target0, unchanged incoming/outgoing event COM bits and event spin bits, certified zero TOI/gap, new shape identity/unchanged body identity, consumed forces, zero-spin/support state and unchanged metadata. It cannot hide a duplicate bounce. Source case8 also passes with no new admission when only restitution material changes during persistent support.

Reused384 first cases,192 patch units,24 narrow acceptance/rejection probes and420 genuinely consecutive source/package frames; no210-frame run was duplicated. Retained verified source lifecycle0–6; ran missing source7–8 and all previously missing package0–8. Package cases0–6 exactly match old successful source rows; cases7–8 exactly match corrected source rows. The original fresh28-module package was reused: the outer lifecycle test is not in its dependency closure, and closure/owner/toolchain hashes are unchanged. Only corrected consumers were rebuilt. No other affected regression exists because no production source changed.

Then72 new preflight advances passed independent shared-domain physical checks, covering each of three methods at matching1/30s duration. All270 plain and54 traced advances also passed. Each full23-word state matches an independent scalar method reference at1e-10*(1+abs(reference)); maximum error/tolerance ratio4.5123374e-6. Strict macro/four-substep contact endpoints retain the original1e-5m slop; candidate endpoints have zero analytic gap. This difference meets the approved temporal position bound plus unchanged geometry representation tolerance. Residual, energy, velocity, orientation/spin, accumulator and rollback gates are unchanged; exact state equality between different stepping methods is not claimed.

The finite benchmark uses the unchanged strict96 zero-friction response, once after a full macro integration or after each of four complete1/120s integrations. Four-substep force is resubmitted after each clearing step, so all methods apply the same continuous force over the macro. The measured scope includes every force submission and complete integration/response or temporal advance, existing registry reconciliation, publication, synchronization and scalar status/report maps. Setup/context creation and extra diagnostic readback are excluded. There are three balanced sequential fresh-process blocks; each trajectory has10 consecutive frames with the first2 excluded from warm summaries. CUDA/NVTX traces contain6 frames per method/fixture with4 warmed. No CPU sampling, context-switch tracing, memory-usage tracing, CUDA event tracing or Compute counters.

## Complete advance host latency

Median milliseconds;24 warmed observations per method/fixture. Full min/max and per-block values are in performance.json.

|Fixture|Temporal patch|One strict96 macro|Four full strict96 substeps|Result versus macro / four substeps|
|---|---:|---:|---:|---|
|constant-force free flight|1.020|1.777|6.813|0.574× time / 0.150× time|
|quiet support with constant downward force|8.198|4.159|17.283|1.971× time / 0.474× time|
|inelastic-impact-start consecutive support trajectory|8.078|3.973|17.673|2.033× time / 0.457× time|

Support is about97% slower than one strict macro and53% faster than four full substeps. The inelastic-start trajectory is about103% slower than macro and54% faster than four substeps. Warm inelastic-start observations are later support frames, not the initial impact; first-call impact latency is reported separately below. Free flight is43% faster than macro and85% faster than four substeps. These small-case measurements do not support an overall optimization or real-time claim.

## GPU and CUDA API activity

Median milliseconds from4 warmed traced observations per method/fixture. Kernel duration sums use device timestamps; activity spans include copies/memsets and queue gaps. CUDA API durations include waits that overlap GPU execution and must not be added to GPU times. Nsight capture overhead makes traced and plain runs separate measurements.

|Fixture / method|GPU kernel sum|GPU activity span|CUDA API duration sum|CUDA synchronization duration|Kernel launches|
|---|---:|---:|---:|---:|---:|
|0 / temporal_patch|0.924|1.042|1.027|0.970|6|
|0 / strict96_macro|1.628|1.848|1.821|1.717|20|
|0 / four_full_strict96_substeps|6.255|7.233|7.091|6.685|80|
|1 / temporal_patch|8.175|8.370|8.364|8.307|6|
|1 / strict96_macro|4.055|4.272|4.243|4.138|20|
|1 / four_full_strict96_substeps|16.375|17.423|17.270|16.850|80|
|2 / temporal_patch|8.109|8.244|8.231|8.175|6|
|2 / strict96_macro|3.926|4.124|4.093|3.989|20|
|2 / four_full_strict96_substeps|16.046|17.357|17.208|16.799|80|

Temporal contact cost is dominated by its temporal_patch_floor GPU kernel; strict contact cost is dominated by packing the unchanged per-patch operators. Attribution uses NVTX-scoped CUDA launch correlation IDs and verifies the unmodified production enqueue sequence on all54 frames: force3+temporal3=6 launches, force3+integration3+response14=20, or four repeats=80. Kernel symbols, launch dimensions,239 registers/thread for the temporal kernel, zero static/dynamic shared bytes and reported local-memory metadata are retained. Dynamic spills/stalls remain unmeasured; CUPTI localMemoryTotal is not evidence of allocator footprint or spills. No denied-counter retry occurred.

## First-call and event accounting

These are first advances of fresh owners using existing disk/driver caches, not forced-empty-cache measurements. Median of3 plain blocks; first2 calls excluded from warm tables.

|Fixture|Temporal patch first call ms|Strict macro first call ms|Four substeps first call ms|
|---|---:|---:|---:|
|constant-force free flight|3.378|9.020|13.885|
|quiet support with constant downward force|10.571|12.329|24.654|
|inelastic-impact-start consecutive support trajectory|11.179|11.147|25.499|

Candidate TOI admissions: zero throughout free/support trajectories; exactly one in frame0 of each inelastic-start trajectory, then zero. Strict endpoint response exposes patch/point/solve counts, not TOI admissions or bounce-impulse counts; those counters are marked unavailable rather than inferred from four repeated patch solves. Work counters and accuracy maxima accompany every advance.

No benchmark case failed or was unsupported among the prequalified shared-domain set. Six prior unsupported source/package probes remain unchanged: overlap303, initial floor angular motion301, contact torque301, footprint escape304, extra dynamic body301 and wrong macro dt300. Lifecycle friction/restition/dt configurations still reject300 and fixed-floor force rejects301 with exact rollback. These rejection fixtures were excluded from timing, not reclassified as valid. Elastic impacts have prior candidate-only qualification and are not used for a shared endpoint-response TOI accuracy claim. Stacks, friction, rotating contacts, warm seeds and packing are excluded. Original strict caps/gates and63/70 accounting remain unchanged.

Preservation verified: 17,828 protected hashes including preserved prior evidence and corrected outer test; all5,901 asset/save size/mtime identities, 17 campaign sources and119 other source/lock hashes. Mojo1.2.0.dev2026092905 and isolatedMAX26.7.0.dev2026092905 unchanged. Minimum available memory110.418GiB; final113.594GiB; reserve32GiB. One execution slot, single-thread builds, finite guards. H3paused; hardware/driver/power/security/profiling permissions/defaults/precision and unrelated dirty work untouched.

Sealed result: GPU compute list empty; no owned jobs. Evidence: verification.json, performance.json, accuracy.json, reused-successful-evidence.json, corrected lifecycle source/package records, original-failed-lifecycle.mojo, oracle-correction.diff, predeclared.json, correctness-barrier.json, raw plain records, nine CUDA/NVTX SQLite/nsys captures, telemetry/build fingerprints and FINAL-SHA256SUMS.
