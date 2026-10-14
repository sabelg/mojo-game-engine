# Atlas physics publication checkpoint

This archive preserves the saved qualification evidence alongside the experimental
Mojo sources. It is a source and evidence checkpoint, not a new engine release.
`archive-manifest.json` identifies original local receipt paths and SHA256 hashes.
The original `build/` receipts remain untouched. Paths inside archived receipts
refer to their original execution location; compiled packages, executables,
dependency environments and large profiling traces are intentionally omitted.

## Current qualified boundary

- `physics-rotating-floor-vertex/RESULTS.md`: 5,144 saved source/package records
  for an isolated arbitrary-pose, unique-vertex frictionless impact map. Geometry
  refresh, full world inertia, point velocity and physical angular impulse are
  retained. Nonzero friction, edge/face ties and unsupported profiles reject.
  This is not a rotating trajectory, TOI solver or general contact owner.
- `physics-temporal-floor-friction-unilateral/RESULTS.md`: 3,726 bounded
  straight sliding/stopping/holding/oblique-impact correctness records, including
  consecutive one-second trajectories and transactional lifecycle checks.
- `physics-temporal-floor-friction-timing/RESULTS.md`: about 6–13.5 ms per
  fixed 1/30 s advance. Holding is slower than the strict macro reference;
  other strict comparisons fail accuracy admission. No general 60 Hz claim.
- `physics-frozen-floor-friction/RESULTS.md`: restricted fixed-pose pressure
  redistribution. It must not suppress genuine angular motion.

Other directories preserve historical qualifications, experiments and failures.
Their presence is not promotion. Warm starts and lossless packing have not shown
a general performance gain. Difficult multibody performance remains unresolved.
The rotating prerequisite is complete; no subsequent integration or timing was
performed for this checkpoint.

## Recovery validation

On 2026-10-14, all 11 saved rotating build/source fingerprints matched the local
files. The independent Decimal80 invariant checker was rerun against all saved
native source/package records; it passed momentum, angular momentum, energy and
normal residual gates and exact package parity. This was an offline recheck of
recorded GPU outputs, not a new GPU execution. All eight vertices are exercised.

To repeat the offline check with Python's standard library:

```sh
timeout 60 python3 -B docs/physics-evidence/physics-rotating-floor-vertex/check-invariants.py
```

It rewrites only the archived invariant-proof JSON, deterministically. For new
native qualification, read the original design and runner first; fixture paths
and guards expect `build/physics-rotating-floor-vertex`. Never overwrite or
duplicate completed stages. The archived reference generator can reproduce the
fixture TSV files. Native execution requires the existing pinned Mojo
1.2.0.dev2026092905 / MAX 26.7.0.dev2026092905 environment, one execution/GPU slot,
one-thread builds, finite guards and 32 GiB available-memory reserve. H3 remains
paused. No denied profiling counters were retried.

## Publication scope and limits

The checkpoint includes Atlas engine source, experimental physics, tests,
engine tooling, documentation, unchanged toolchain pins and selected numerical
receipts. Existing game projects, asset relocations, third-party assets, saves,
generated binaries/traces, dependency caches, local session/credential state and
the unreviewed game CI workflow are excluded. No existing local files are removed.
The older repository layout and asset files at the base commit remain in Git:
the pending game/content migration is not completed by this source checkpoint.
It is not a qualified fresh-checkout SDK or complete game release.

Publication checks cover UTF-8/text and secret-pattern review, Python syntax,
shell syntax, diff whitespace, source fingerprints and the independent saved
physics evidence. The local engine dependency-boundary check passed. The full
native engine/game suite and fresh-checkout asset-layout checks were not rerun;
the historical receipts retain their original scope. No new CI workflow is
enabled by this checkpoint.

Whitespace checking reported pre-existing trailing whitespace and blank EOF
lines in several historical sources/tests and `scripts/qualify-usd.py`. Those
files were preserved byte for byte to retain qualification fingerprints; the
whitespace check is not reported as passing. Python and shell syntax checks
passed. The original rotating report mentions a `FINAL-SHA256SUMS` file that
was not present on recovery; this archive supplies its own explicit manifest
and verifies the saved build fingerprints instead of claiming that missing seal.
