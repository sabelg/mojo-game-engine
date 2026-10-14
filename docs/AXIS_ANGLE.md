# Quaternion axis-angle correctness checkpoint

`Quaternion.axis_angle(axis, angle)` treats an axis as a direction. The prior
1e-12 length guard called `Vec3.unit`, whose 1e-6 zero fallback erased accepted
small axes. `(0,0,1e-8)` at pi/2 consequently rotated `(1,0,0)` to itself rather
than `(0,1,0)`. Directly squaring raw components also lost tiny axes to underflow
and large axes to overflow.

The factory now divides components by their largest absolute component before
computing the length. At least one scaled component has magnitude one and all
are bounded by one, so the sum of squares lies in [1,3]. Direct division avoids
forming an overflowing reciprocal of a tiny raw scale. No magnitude threshold
selects identity for a finite nonzero direction.

The non-throwing public contract is:

- Every finite nonzero binary64 axis supplies its direction, including subnormal
  components and axes whose mathematical norm exceeds the largest Float64.
- An exactly zero axis, including signed zeros, returns identity before angle
  validation. This preserves the existing zero-axis fallback for every angle.
- A nonzero non-finite axis or non-finite angle returns an all-NaN quaternion,
  retaining detectable invalidity rather than converting invalid input to identity.
- Very small nonzero axes intentionally stop acting as implicit identity. Callers
  wanting an application cutoff must choose it explicitly. Function signatures,
  layout and radians convention are unchanged. `Vec3.unit` and the separate
  `Quaternion.normalized` thresholds are unchanged.

Binary64 rounding still applies. A normalized component smaller than the least
subnormal may become zero. Half of the least positive subnormal angle rounds to
zero, so that increment cannot survive the half-angle construction. Standard
CPU sine/cosine range reduction is retained; this checkpoint makes no additional
accuracy guarantee for extreme angles or arbitrarily scaled quaternion storage.

`tests/axis_normalization.mojo` checks 34 positive/negative axes and 510 rotations
against scalar Rodrigues using directions independently generated at 1200 Decimal
digits from exact binary64 inputs. Cases span the least subnormal, minimum normal,
old thresholds, squared-norm overflow/underflow, maximum finite components and
mixed extreme ratios. Analytic quarter turns, sign/angle equivalence, inverse,
norm/projection preservation, zero/non-finite cases and representation limits are
explicit. `tests/vector_rotation.mojo` retains its 90 original cases and exact
small-axis regression. Both CPU tests ship in the source SDK and normal build/test
workflow.

The locked NVIDIA Mojo backend does not support the factory's Float64 sine/cosine.
The actual GPU test supplies CPU trigonometric coefficients and executes the
production private normalization/assembly helper and `Quaternion.rotate` on the
device, with independent Rodrigues expectations and buffer/tail guards. It does
not claim that the full public axis-angle factory can run on this GPU. Existing
physics device integration retains its separately qualified bounded polynomials;
no trig backend or physics algorithm was changed.

Reproduce with `python3 scripts/qualify-axis-normalization.py MODE --slot-confirmed`,
where MODE is `cpu`, `packaged-cpu`, `gpu` or `packaged-gpu`. This uses the existing
matched Mojo/MAX environment, one compiler thread, 180s compile/30s execution
bounds, 32 GiB reserve and temperature observation only. H3 stays paused.

Recovery and final qualification evidence:
`build/axis-normalization-recovery/verification.json`.
Original failing audit and rollback copies remain under
`/home/user/Documents/Codex/2026-10-12/task/axis-normalization-fix-20261013` and
`/home/user/Documents/Codex/2026-10-12/task/hepjo-math-audit-20261013`.
No HEPJo code, fixtures or dependency was imported.
