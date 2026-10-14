# Rotating-contact continuation checkpoint — 2026-10-14

This source/tests/evidence checkpoint extends the earlier isolated impact result.
It is experimental, not an engine release or a general multibody solver.
The 71 added Mojo files include historical alternatives; inclusion is not promotion.
All 71 match the protected source fingerprints from the saved investigations.

## Qualified scope and unresolved boundary

The cooperative DP baseline measured 40.607–42.926 ms for its qualified fixed
1/30-second single-switch API. It does not meet 33.333 ms and does not establish
60 Hz or GPU scaling. The older restricted straight friction implementation
measured about 6–13.5 ms per 1/30-second step; static holding was 28–29% slower
than its strict macro reference and about 66% faster than four substeps. Other
strict comparisons were invalid. The difficult multibody case remains about
460 ms. Warm starts and lossless packing are not promoted.

The compensated owner clock carries state, error history and the original
impact episode across macros. Seven cases commit four macros (about 0.133333 s);
two translated cases stop after three. No fifth macro commits. The positive-gap
geometry rule permits a released vertex to turn toward the floor while still
separated; it does not apply an impulse at that turn. The independent first
recontact estimate is 0.301324646320388 s. Native motion cannot reach it under
the existing cumulative roundoff budgets. No through-turn, one-second rotating,
stacking, general multibody or new timing claim is made.

The separated-gap qualification contains 84 geometry and 144 owner/control
records with exact source/package replay and rollback, plus 35 converged
independent reference trajectories for private prefixes. The latter are not
committed macro advances. Reaction, point velocity, inertia, geometry refresh,
friction/restitution exclusions and episode ownership remain as documented in
the accompanying results and numerical contract. Genuine rotation is retained.

The roundoff investigation is paused for publication review. At rejection,
90.21–97.58% of the ledger increase is transport/outward growth, rather than
new local noise charges. Its 17-map Decimal100 diagnostic has unresolved
bit-replay mismatches; it does not qualify a tighter bound or compensation fix.
No correction, allowance increase, uncertainty reset or new native run occurred.

## Evidence and reproduction

The subdirectories copy selected results, verification metadata, package/source
fingerprints and the unchanged numerical contract. `receipt-manifest.json`
records their original paths and SHA256. Original build receipts, raw fixture
and output streams, executable packages and profiling traces remain local and
are not bundled here. This compact archive is not a standalone full trajectory
reproduction kit. Paths inside copied reports refer to the original workspace.
Earlier reports retain their historical no-publication statements.

Run `python3 -B docs/physics-evidence/rotating-continuation-20261014/verify-checkpoint.py`
from the repository root to verify the 71 source hashes and copied receipts.
This checks preservation, not numerical correctness or a fresh GPU execution.
Existing `experimental/physics_gpu/test_*.mojo` files provide native test entry
points; their imports and case comments define the individual scope.

Native work requires Mojo 1.2.0.dev2026092905 / MAX 26.7.0.dev2026092905,
one execution/GPU slot, single-thread compilation, finite timeouts and at least
32 GiB available memory. H3 remains paused. Preserve failed receipts and all
accuracy gates. No native, game-wide or engine-wide suite was rerun for this
publication checkpoint.
