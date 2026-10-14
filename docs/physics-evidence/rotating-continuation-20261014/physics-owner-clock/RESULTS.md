# Compensated-clock owner renewal — correctness result

**Qualified:** all nine cases reach three consecutive macros (exact 3*h, approximately 0.1 s). Seven reach four macros (exact 4*h, approximately 0.1333333 s). The two-word global clock, owner generation, original impact history, shared event-time uncertainty, cumulative E/R/T, minimum allowances and conservation ledgers survive each boundary. No impact is replayed and angular motion remains live.

The preferred cooperative DP baseline remains unchanged. No timing, one-second, general multibody or 60 Hz claim is added.

## Evidence

- **404 final trajectory/control records:** 212 accepted and 192 rejected, with 202 exact source/package comparisons. Raw Float64 bits are used for fixture transfer, receipt readback and rollback checking.
- **696 clock records:** 87 vectors, four replays on each build path. Independent exact-rational arithmetic checks small/subnormal increments, increments below the high word's ulp, cancellation of low words, all fixed-step clocks through one second, and atomic rejection of an unrepresentable third residual. Clock-only coverage is not a physical one-second trajectory claim.
- **80 independently converged full trajectories** support the 16 accepted new boundaries. Macro three uses 256/512/1024/2048 panels and macro four uses 512/1024/2048/4096, with the finest level at Decimal precision 80 and 50. These references apply the independent analytic single-contact impulse once, then check momentum, both angular-momentum ledgers, energy, contact work, geometry, convergence and the reference quarter-budget reserve. They were rechecked against the final bit-exact receipts.
- Maximum native endpoint error plus reference uncertainty is **0.131936 of the carried enclosure**. Maximum active gap is **1.644e-13 m**, active point speed **4.772e-16 m/s**, and raw quaternion squared-norm defect **4.001e-11**. All original gates remain unchanged.
- **16 late-failure cases** finish all private cells and then reject at the final RHS allowance. Every failure preserves all **16,576 entering state/history words** after committed prefixes. Retry reproduces the successful receipt without charging loss twice. Additional controls cover stale generation, stale high/low clock, complete stale owner/history, invalid ownership, phase, episode, state/history mismatch, changed origin input, unsupported physics, exhausted error and invalid work requests.
- Every accepted third-macro clock is `(0.1, -6.938893903907228377647697925567626953125e-18)`. The fourth is `(0.13333333333333333, 0)`. Both equal the exact requested multiple of the original binary64 step; no small increment or remainder is discarded.

## Genuine stopping boundaries

**Translated-origin cumulative roundoff.** Negative-x case 6 and positive-z case 7 reject macro four at private cell 12, whose trial endpoint is approximately 0.125 s. Their last committed time remains 3*h. The fixed-origin moment roundoff bounds reach approximately **2.51489e-11** and **2.50855e-11**, exceeding the unchanged **2.5e-11** quarter-budget. This is an uncertainty-enclosure limit, not evidence of physical momentum loss. A tighter justified cumulative roundoff enclosure is needed; resetting the budget is not permitted.

**Released-vertex opening domain.** The other seven reject the first cell of macro five with 2204. Its conservative opening lower bound is approximately **-0.00581987 m/s**, although the entering released speed is **0.0840263 m/s** and the independently computed first-cell endpoint speed is **0.0748044 m/s**. Thus the earliest native rejection is conservative.

A refined independent diagnostic brackets a genuine opening-to-closing turn near **0.152430463119 s**, within macro five. The released vertex remains about **0.04650778 m above the floor**, with positive support reaction and separated other vertices. This is **not recontact or an impact**. The current opening-only domain cannot accept the complete fifth macro. Further progress needs a sharper whole-cell opening certificate and explicit handling of a separated vertex turning toward closing. No native state beyond the supported domain was forced through.

## Implementation and retained attempts

`owner_clock.mojo` implements checked error-free addition with an explicit third-residual rejection. `owner_clock_advance.mojo` renews verified owners, uses both global-time words in momentum and interval bookkeeping, and preserves the original event-time charge. CONTRACT.md specifies the schema, provenance requirement and exclusions.

The four-attempt Picard inclusion gate and all work caps are retained. An initial two-ulp inclusion stall was traced to unnecessarily enlarging already-included components. The final update enlarges only failing components with outward rounding padding. The unconditional-padding attempt and all rejected receipts remain preserved.

The final checker also caught a one-ulp change during decimal fixture parsing. Native rollback preserved the parsed value, but that did not prove transfer of the original history bits. The final harness uses two exact 32-bit halves per Float64 and raw UInt64 readback. The decimal suite is preserved and superseded for exact-transfer qualification. Final decimal output formatting had zero differences from raw readback bits.

The initial fourth-macro reference's intermediate-stage speed exceeded 1e-9 at 2048 panels; refinement to 4096 passed the unchanged gate. Coarse diagnostic root trials and test-harness compile failures are also preserved. None justified an accuracy relaxation. There are **412 final native calls** and **906 total calls including preserved attempts**.

## Preservation and remaining state

The audit verifies **7,221 protected prior hashes**, **7,108 asset/save stat identities** including the original 5,901, unchanged HEAD and prior modules, exact Mojo 1.2.0.dev2026092905 / MAX 26.7.0.dev2026092905 pins, and all 48 package source files. Available memory stayed above **110.51 GiB**, exceeding the 32 GiB reserve. Compilation and execution remained guarded and sequential.

H3 remains paused. No execution or GPU jobs remain. No publication, system/driver/power/security changes, denied counters or new runtime measurements occurred. The two stopping prerequisites above are diagnosed; no approval or denied action is pending.

Authoritative evidence: verification.json, correctness-bits.json, reference-bits-recheck.json, boundary-final.json, boundary-refined.json, preservation-audit.json, raw-bit receipts and FINAL-SHA256SUMS.
