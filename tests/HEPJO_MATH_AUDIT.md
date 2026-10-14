# HEPJo source assessment and independent Atlas math tests

Inspected revision `99394a257555eea421344a00aa31836ad92d0e32` read-only. HEPJo
was not installed, imported, compiled or executed. Its pinned manifest targets
osx-arm64 and MAX >=24.6.0,<25, so it is not a runtime dependency for this checkout.

Useful idea: compare quaternion rotation with independently implemented standard
Rodrigues identities. The new `tests/vector_rotation.mojo` uses scalar dot/cross
components and its own axis normalization; it calls no production quaternion or
Vec3 helpers in the oracle. Its coordinates and code were authored independently,
not copied/adapted from HEPJo. Source and isolated precompiled production-math
copies passed 90 principal/general-axis cases, 0/90/180-degree checks, inverse,
norm/projection and representation/axis scaling identities. Zero/near-zero
fallbacks and adjacent-field canaries are separate checks. Atlas Vec3 has three
named Float64 fields; it has no HEPJo fourth-lane layout to adopt or contaminate.

HEPJo's scalar arithmetic uses all four allocated lanes, while dot/mag/mag2 reduce
four lanes. A scalar addition can therefore contaminate its padding contribution.
Its unit method divides zero magnitude without a zero guard. These are static
source inferences, not executed upstream failures. Its existing test_vector file
mostly checks basic arithmetic; it does not provide the independent rotation
coverage needed here. No heap/SIMD layout or fixtures were imported.

The audit also confirmed an existing Atlas issue. `Quaternion.axis_angle` accepts
length >=1e-12 but calls Vec3.unit, whose length<1e-6 fallback is zero. For axis
(0,0,1e-8), angle pi/2 and vector (1,0,0), the known-failing probe returns
(1,0,0), instead of (0,1,0), with quaternion norm squared 0.5000000000000001.
The independently predicted component error is 1.0. Production code is preserved
because this increment was explicitly an assessment/test addition. The failing
probe is in evidence, outside the passing suite; it is not treated as a correct
contract or a passing mathematical test. A narrowly scoped normalization fix
remains future work.

Existing physics/inertia tests already cover quarter turns, rotated tensors and
quaternion norm through trajectories. The new independent Rodrigues comparison
and scale/inverse/neighbor cases fill the targeted gap without replacing those tests.
The current recommended GPU review uses supported axes and its nineteen verified
integration fingerprints remain unchanged.

LICENSE inspected at the exact revision: Apache 2.0 with LLVM exceptions. No
HEPJo-derived implementation or numeric fixtures are included, so no third-party
license/notice additions were made. This provenance note credits the source
assessment separately from independently implemented mathematical identities.

Sources (pinned):
- [Vector implementation](https://github.com/shivasankarka/HEPJo/blob/99394a257555eea421344a00aa31836ad92d0e32/hepjo/vector/vector3d.mojo)
- [Vector helpers](https://github.com/shivasankarka/HEPJo/blob/99394a257555eea421344a00aa31836ad92d0e32/hepjo/vector/math_funcs.mojo)
- [Upstream tests](https://github.com/shivasankarka/HEPJo/blob/99394a257555eea421344a00aa31836ad92d0e32/test/test_vector.mojo)
- [Manifest](https://github.com/shivasankarka/HEPJo/blob/99394a257555eea421344a00aa31836ad92d0e32/mojoproject.toml)
- [Exact license](https://github.com/shivasankarka/HEPJo/blob/99394a257555eea421344a00aa31836ad92d0e32/LICENSE)

Reproduce the passing source suite with the pinned project compiler:
`mojo build --num-threads 1 tests/vector_rotation.mojo -I . -o /tmp/atlas-vector-rotation`
then run that executable. This audit used the existing 180s compile/30s execution
bounds, one thread, exclusive slot and 32 GiB reserve. It executed CPU math only,
with no rendering, new dependencies, production/SDK changes, settings changes
or H3 resumption. Detailed commands/logs/fingerprints and the separate failing
probe are in this evidence directory's `verification.json`.

## Subsequent production repair

The earlier failing audit above remains historical evidence. The recovered
axis-angle repair now replaces the conflicting length thresholds with scaled
normalization and an explicit zero/non-finite contract. The exact old probe is
in the passing suite. Independent Decimal direction fixtures cover binary64
extremes through source/precompiled CPU and actual device normalization/rotation.
See [axis-angle contract and limits](../docs/AXIS_ANGLE.md) and
`build/axis-normalization-recovery/verification.json` for final repair evidence.
The original failure, numerical gates and GPU physics baselines are retained.
