# Separated turn geometry qualified; cumulative trajectory stops before the turn

The new geometry prerequisite distinguishes a separated vertex turning toward closing from contact. It passes independent/source/package tests before, across and after the turn. **No native fifth macro was committed:** the unchanged cumulative roundoff gates reject all seven progression cases before the turn. The two earlier translated-case failures are retained and replayed unchanged.

## Physical rule

Retained support remains vertex 4. Released vertex 5 may have positive, zero or negative normal point velocity while separated. A velocity sign change alone applies no impulse and does not change contact identity or impact history.

For every cell, the new helper bounds the entire released gap by the concave lower parabola

`g(t) >= g_lower + u_lower*t - A*t²/2`, for `0 <= t <= h`.

Here `u = (v + omega cross r).y`; A bounds translational acceleration, coupled support reaction, angular acceleration and centripetal acceleration. It uses the existing spherical-inertia/positive-reaction bounds and refreshed body/shape geometry. The minimum of this lower parabola is at an endpoint. Acceptance requires both endpoints' lower bound to exceed the unchanged **1e-9 m contact band**. All retained-support gap/speed, reaction, other-vertex exclusion and state gates remain intact. Failure returns 2604: separation is unproven, not an instruction to apply an impulse.

This is for an already separated vertex, not a replacement for the older zero-gap release handoff. Friction/restitution remain zero, external force constant and external torque zero. There is no planar pressure shortcut, angular suppression or normalization of the stored quaternion.

## Qualified evidence

- **84 geometry records** cover 21 cases on source and package with replay: 19 positive-gap cases and two rejections. Cases span a chronological separated reference path, before/at/after the turn, the interval containing recontact, and the contact-band state itself. The old opening-only helper rejects the three turn fixtures; the new gap helper accepts them without changing any input state or ledger.
- An independent Decimal checker verifies the lower-parabola inequalities and point-velocity geometry. Geometry-unit radii are fresh unit inputs; they never replace, reset or bypass the production owner's E/R/T history.
- **144 owner/control records** pass exact raw-Float64 source/package and rollback checks: 60 accepted recovery records and 84 rejections. All 16,576 entering state/history words are preserved on failure. A late work-cap failure after 16 private cells and repeated budget failures after committed prefixes are included, along with stale-owner, clock, episode/loss and unsupported-physics controls.
- **35 independent converged full-reference trajectories** validate the seven new private accepted prefixes, including analytic original impulse, momentum, both moment ledgers, energy, contact work, geometry and the reference quarter-budget. Worst endpoint error plus reference uncertainty uses **0.085824** of the carried enclosure. These are private prefixes, not new macro commits.
- Recovery runs reproduce the already-qualified fourth-macro physical state, compensated clock and E/R/T exactly. Only the experimental owner-version markers and geometry diagnostics change. The original impact loss and contact episode are never reapplied.

## Exact native stopping boundaries

| Cases | Last committed time | Failing trial time | Exhausted R component |
|---|---:|---:|---|
| 0–4: ordinary, enumeration, perturbations, raw-Q defect | approximately 0.1333333 s | approximately 0.1520833 s, cell 9 | Normal impulse |
| 5: positive-x translation | approximately 0.1333333 s | approximately 0.1395833 s, cell 3 | Fixed-origin moment z |
| 8: negative-z translation | approximately 0.1333333 s | approximately 0.1375 s, cell 2 | Fixed-origin moment x |
| 6: negative-x translation, pre-existing failure | approximately 0.1 s | approximately 0.125 s, cell 12 of macro 4 | Fixed-origin moment z |
| 7: positive-z translation, pre-existing failure | approximately 0.1 s | approximately 0.125 s, cell 12 of macro 4 | Fixed-origin moment x |

For cases 0–4, R reaches approximately **2.5289e-11**, above the unchanged **2.5e-11** allowance. The ninth-cell trial ends before the reference turn near **0.152430463119 s**. E and T remain within their quotas, but that does not authorize accepting an exhausted R quota. The two pre-existing translated failures retain their exact entering state/history and rejection quantities; they were not silently excluded.

The next prerequisite is a tighter, justified cumulative roundoff enclosure for normal impulse and fixed-origin moments. No error reset, relaxed allowance, changed work cap, skipped remainder or partial macro publication was used to force progress.

## Turn versus first actual recontact

Independent diagnostic references locate vertex 5's first recontact near **0.301324646320388 s**, long after its separated turn near 0.152430463119 s. At recontact its normal speed is approximately **-0.610244846371 m/s**; vertex 4 remains supported, reaction is positive, and the nearest competing vertex is over **0.10394659 m** clear.

Chronological geometry certificates clear the path to the final candidate interval. In that interval, the released velocity upper bound remains negative (approximately **-0.0726485 m/s**), establishing the local monotone closing condition. Competing vertices are excluded, including the two vertices after the rejected vertex in loop order. Independent 128/256/512-panel-per-0.01-second references and a 50-digit run converge within the existing 1e-13/1e-35 gates. Fine-reference retained-support gap and speed remain below 1e-9.

This is a **diagnostic first-root result**, not an admitted native trajectory or a new collision response. Right-side probes serve only to bracket the zero. No post-contact state or impulse is published. Existing event-location principles apply locally to the isolated closing bracket, but the native locator was not invoked: cumulative uncertainty had already made the production owner ineligible well before this time. Reusing it as a fresh query would not repair that history and could not justify resetting the budget.

## Preservation and limitations

The preferred cooperative DP baseline and all earlier evidence remain intact. All work is isolated in two new experimental modules and this directory. The final suite uses **228 native calls**; **246 total calls** include the initial preserved rejection probe. One checker initially compared differently rounded 50/80-digit time strings; it was corrected to the established numeric 1e-35 precision gate. The difference was 2.8125e-51. The failed checker log remains preserved.

See verification.json and preservation-audit.json for protected hashes, all asset/save identities, exact Mojo/MAX pins, finite guards, memory reserve and final empty job inventory. H3 remains paused. No publication, system/driver/power/security change, denied counters or timing campaign occurred. There is no native through-turn, fifth-macro, one-second, multibody or new performance claim.
