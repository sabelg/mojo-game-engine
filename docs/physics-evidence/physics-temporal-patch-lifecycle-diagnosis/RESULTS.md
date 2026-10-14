# Shape replacement mismatch: wrong zero-counter oracle

The sealed candidate's response is correct for the frozen replacement fixture: it invalidates the old shape generation, discovers contact for the new identity, applies no duplicate restitution, and ends in physically correct support. The failed test conflates a private TOI-admission counter with the number of restitution impacts. Its hardcoded zero-counter expectation is wrong for this exact saved state. No implementation, oracle, gate, budget, or prior evidence was changed during this diagnosis. The earlier stopped qualification receipt remains intact; this diagnosis does not promote the candidate.

One diagnostic-only replay was necessary because the sealed lifecycle row contained only error/event/combined predicate, without post-replacement state or identity snapshots. The reproducer imports the unchanged sealed package and executes only kind7: create floor and box, advance quiet support once, set force(0,-4,0), detach/attach the same geometry, advance at e=1. Five snapshots record after support, after force, after detach, after attach and after advance. No other fixture, qualification or performance run occurred.

|Identity or state|Before replacement|After replacement|
|---|---|---|
|Dynamic body slot/generation|1 / 1|1 / 1|
|Floor body slot/generation|0 / 1|0 / 1|
|Dynamic shape slot/generation/revision|1 / 1 / 1|1 / 2 / 1|
|Floor shape slot/generation/revision|0 / 1 / 1|0 / 1 / 1|
|World namespace|same|same|
|Body metadata bytes|unchanged|unchanged|
|Four geometric gaps|all0m|all0m|
|COM normal velocity|−2.0816681711721685e−17m/s|same before advance|
|Force|0,−4,0N|same before advance|

There is no separate body revision counter in this base GpuWorld. SET_FORCE changes only force/torque; it leaves generation and the first17 physical-state fields unchanged. Shape detach increments generation to2 and clears revision/ownership; attach reuses slot1, keeps generation2 and starts revision1. Revision resetting to1 does not preserve identity because generation differs.

The old episode remains stored until successful macro publication but becomes **ineligible**, rather than being reused. Before replacement its valid/touching flags are1/1 and all11 key words plus the first17 dynamic/floor state words match. SET_FORCE alone remains eligible because force fields are excluded. Detach/attach changes only the dynamic shape generation word in the reconstructed complete key. The subsequent successful publication stores the new key with valid/touching1/1. Registry/history identity therefore has a genuinely new contact episode; there is continuous resting geometry, without a new macroscopic collision. These are distinct facts.

The counter's semantics follow its placement in temporal_patch_floor_kernels.mojo: summary[2] increments for a found TOI root **before** physical restitution target selection. It counts TOI-admission batches, including zero-time low-speed admissions. It counts neither only restitution impulses nor all new registry episodes: a fresh exact-zero-speed contact can take direct support with zero batches. Existing history_transaction separately labels changed generation NEW and unmatched old identity ENDED; the temporal owner uses those same11 identity fields but does not call the history API. The frozen temporal contract requires physical incoming restitution once per episode and at most4 batches, but never promises zero TOI admissions after replacement.

The causal branch is small: same-key eligibility would retain touching; the changed generation makes it false. Fallback admission then requires exactly b.linear.y==0, which the verified negative Float64 roundoff does not satisfy. Zero gap and descending speed admit a certified t=0 root. No force kick or drift occurs before this root. The measured incoming and outgoing event COM velocities are bit-identical at −2.0816681711721685e−17m/s; the restitution target is0 because incoming is far above the −0.2m/s threshold. All four incoming point speeds are within the original1e−9 residual tolerance. Mask0/zero impulse is feasible and has globally minimum norm, proving no event impulse is applied. The remaining macro uses ordinary support corrections. The exact-zero-velocity and retained-key alternatives are shown as offline algebraic controls, not additional GPU runs.

Independent scalar quaternion/corner calculations confirm all gaps and row speeds. Final y=.5m, vy=−1.5612511283791264e−17m/s, and spin are within the original strict analytic gates; force and torque are consumed. Total normal impulse0.7873333333333334kgm/s balances2kg×11.81m/s²×1/30s, with momentum balance error−1.1102230246251565e−16kgm/s. Maximum contact kinetic-energy gain is3.987276837989199e−35J. All original case7 predicates pass except events==0. The single new TOI admission is valid cold discovery, not stale reuse, duplicate restitution or a second positive-time impact.

Minimal correction proposed, **not applied**: in test_temporal_patch_lifecycle.mojo:46, change only

```mojo
events==Int32(1 if kind==5 else 0)
```

to

```mojo
events==Int32(1 if kind==5 or kind==7 else 0)
```

This exact fixture must expect one certified TOI admission. Clarify that the local variable means TOI batches; retain every physical state, force-consumption, spin, fresh-key and metadata gate. In follow-up qualification, explicitly verify the new shape generation, unchanged body generations, zero restitution target and no bounce. Do not change the candidate's exact-zero admission, root solver, tolerances, restitution threshold or budgets to make this diagnostic counter zero. A separate proposal would be needed if a public API were intended to count energetic impacts instead.

Remaining qualification work is unchanged: source/package lifecycle case8 and package lifecycle checks, then any separately authorized matched-duration comparison. No performance benchmark was run; dynamic spills/stalls remain unmeasured. Resource and preservation receipts are in verification.json; the original candidate verification SHA-256 remains71bdb8a3b97625a0c915de8ef2ab69e5193efcd40fb89d987b678e494f283e8b.

Final seal: 17,806 protected hashes, all5,901 asset/save identities, 17 campaign sources and119 other source/lock hashes verified unchanged. Pinned Mojo1.2.0.dev2026092905 / isolatedMAX26.7.0.dev2026092905 unchanged. Minimum available memory111.865GiB; final113.640GiB; reserve32GiB. One execution slot, one-thread compile, finite180s build/30s native guards. GPU compute list empty; no owned jobs. H3remained paused; no dependency, driver, power, security, profiling-permission, precision or default changes.
