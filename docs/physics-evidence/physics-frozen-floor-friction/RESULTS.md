# Frozen coupled floor-friction block: restricted-domain positive result

Implemented only a separate frozen-pose kernel and physical test consumer. The qualified temporal/frictionless owner, all prior sources, failed receipts and evidence remain unchanged. No full advance, trajectory, warm cache, compression, default replacement or benchmark was added. The cheap coupled formulation satisfies every point's existing circular Coulomb maximum-dissipation law in the admitted matrix; no broader solver is proposed on this evidence.

## Equations and domain

At one certified rectangular face, reconstruct the current-group free generalized velocity by subtracting the ALREADY-APPLIED old normal+tangent wrench from current state. Let n=+Y, r_i=(x_i,-h,z_i), current-group normal target beta, mass m and supplied positive inertia tensor I. The trial sets

    N=m(beta-v_n*) >=0,
    T = argmin_[|T|<=mu N] { |T|²/(2m) + v_t*·T },
    c=-h T/N,
    lambda_i=N/4 [1+x_i c_x/a²+z_i c_z/b²],
    t_i=(lambda_i/N) T.

For N=0, both impulse components are zero. The total tangent solve calls existing disk_min withI₂/m once, rather than using the generic8x8 Newton/line-search pipeline. This effective metric is valid because the pressure distribution cancels the entire contact torque: sum(lambda)=N, sum(x lambda)=-h T_x, sum(z lambda)=-h T_z, and sum(r×[lambda n+t])=0. The proportional tangent distribution has zero yaw moment. It is not infinite inertia and not an angular clamp.

The actual update is delta_J=sum(J_new-J_old), delta_tau=sum(r×[J_new-J_old]), v+=delta_J/m and omega+=I_world^-1 delta_tau. Positions, orientations, force/torque fields and supplied mass/inertia are never modified. Negative normal/tangent deltas and already-correct idempotent seeds are exercised. Actual angular output may contain roundoff; it is never forced to zero.

Supported qualification domain: one fixed, axis-aligned, simultaneous planar face; uniform incoming rigid translation with zero reconstructed angular motion except strict analytic roundoff; no applied torque; m=.1,2,100 and four valid supplied inertia/geometry variants; 0<=mu<=2; current normal target consistent with e in[0,1]; compressive or zero load; strictly positive minimum-norm pressure certificate

    |c_x|/a+|c_z|/b < 1-256 binary64eps.

This diamond is deliberately narrower than the rectangular convex support hull. Boundary pressure and hull-interior points outside the diamond reject as domain exclusions; they are not generally impossible contact states. CoP beyond the convex hull is physically infeasible for flat torque-balanced support with the prescribed maximum-dissipation impulse. The solver rejects rather than reducing friction or projecting CoP to fabricate flat motion. Nonuniform slip, rolling, yaw/rotation, contact torque, malformed face geometry and separating/inadmissible restitution targets reject.

A total disk alone cannot establish the per-point law. The checker reconstructs the complete12-row contact metric G=J M^-1 J^T (rank6), with normal block rank3, and verifies each actual row. For pressure lambda and local tangent sigma:

    w_n=q_n+G_nn lambda+G_nt sigma;
    lambda>=0, w_n>=0, lambda*w_n=0;
    v_t=q_t+G_tn lambda+G_tt sigma;
    sigma_i = disk_min(K_ii, v_t,i-K_ii sigma_i, mu lambda_i).

Every local disk radius is mu lambda_i, not mu N. Pointwise cone and maximum-dissipation checks are required even when the total disk is feasible. The full contact Gram is singular PSD; that fact does not make the old nonlinear Coulomb Jacobian symmetric/SPD. No nonlinear Jacobian factorization is used here.

## Bounded qualification

26 frozen cases ×4 mass/inertia/geometry variants ×24 point orders × tangent bases0/45/90 =7,488 records per path. Source and fresh28-module dependency package records are byte-identical:4,320 accepted and3,168 expected rejections each,14,976 total. No physical counterexample occurred inside the admitted matrix. Both compile paths and all native batches passed; no gate or solver tuning followed native observations.

Accepted cases cover mu0 normal-only parity; axial and oblique slip; interior stick; static impulse thresholds below/equal/above mu N; oblique restitution e=.5 and1; tiny and zero normal budgets; over-applied, reversed-direction and idempotent retained group seeds; and an increasing-budget stick/slip seed. Retained seeds are private algebraic current-group states, not cross-frame warm starts or genuine integrated time transitions. The frozen threshold velocities encode tangential/normal force-impulse ratios; continuous static-force holding is not yet qualified.

Expected rejections cover boundary/outside/diamond-excluded pressure, reconstructed spin, applied torque, tilted/separated faces, separating normal motion, invalid coefficient/basis and energy-producing restitution target. Rejected body/impulse words are bit-exact copies of input; all64 input words and both output canaries remain unchanged. The trial has no identity cache or body/shape registry, so it makes no new lifecycle claim; existing qualified lifecycle evidence is preserved.

Independent CPU validation uses a manually assembled12-row rigid metric, different scalar elimination/nullspace normal reference, and spectral2x2 disk solve. It checks normal minimum-norm pressure conditional on all actual tangential impulses, every point's normal complementarity and friction optimum, full linear/angular impulse balance, zero net contact torque, and the quadratic impulse energy identity. An additional offline all-active equality/nullspace solve checks tiny-load minimum-norm pressure without classifying small compression as zero merely due to physical residual tolerance. All four matrices have normal rank3 and full rank6.

- CPU_normal_residual: 8.2498814443e-16
- CPU_disk_residual: 4.008690457e-16
- cone_excess: 8.881784197e-16
- state_ratio: 6.93889390391e-06
- momentum_error: 4.93019032514e-15
- angular_error: 1.42731681407e-14
- energy_identity_error: 8.881784197e-16
- Exact equality minimum-norm pressure error/tolerance ratio: 7.55896527404e-06

State comparisons retain1e-10*(1+abs(reference)); normal/tangent velocity residuals retain1e-9*(1+input corresponding speed); per-point cones retain1e-12*(1+radius); energy gates retain1e-9*(1+entry kinetic). Both original current-state and reconstructed-free-state energy gates must pass. Linear/angular balances use the supplied mass/inertia; agreement with a reduced formula alone is insufficient.

## Worked oblique result and an incorrect shortcut

For m=2, I=(4/3,4/3,4/3), a=h=b=.5, mu=.2 and v*=(.3,-.1,.4), beta=0: N=.2kgm/s, T=(-.024,-.032)kgm/s and CoP=(.06,.08)m. The four pressures are(.036,.052,.048,.064)kgm/s, yielding v+=(.288,0,.384)m/s with only angular roundoff. Every individual disk saturates in the common slip direction and all normal rows close.

Counterexample to total-disk-only/uniform-pressure friction: keeping lambda=.05 at all four points gives the SAME admissible total T but net angular impulse(.016,0,-.012)kgm²/s. It induces omega=(.012,0,-.009)rad/s and normal row error up to.0105m/s, vastly above1.1e-9. Clamping that spin would violate angular momentum. Pressure redistribution, rather than independent scalar-corner correction, is essential. This counterexample is independently derived from saved fixture arithmetic; no extra GPU job was launched.

## Stopping handling remains a separate proposal

No distance, stopping-time, one-second friction, impact timing or performance claim follows from frozen blocks. For a future collinear sliding lane, compute t_stop=u/(mu g_eff-F_parallel/m) from physical segment-entry speed before any full-interval kick, when the denominator is positive. Split only that actual segment, use event-sized external/contact half-kicks with matching current-group budgets, then certify static holding or breakaway for the remainder. Never give each point/microgroup the whole macro load or apply restitution again at a stopping event.

This enforces the SAME approved position bound; it does not require relaxing accuracy. Unsplit half-kick clipping can lose17.03125um atmu=.2 and1/120s, exceeding the approved10um macro bound. Keep four base intervals, the existing impact cap and six-segment ceiling; stopping admissions need separate counters. Predeclare how stop/breakaway events consume the existing ceiling and reject overflow. A new event type/bookkeeping is an actual contract addition; increasing a segment/impact cap, adding base substeps, changing coefficient law or loosening gates would be separate changes and is not proposed. The earlier design's accuracy-decision language must not be read as requiring permission to relax a bound that is being preserved. Full integration remains outside this task.

Preservation: 18,379 protected hashes, all5,901 asset/save identities, 17 campaign sources and119 other source/lock hashes unchanged. Pinned Mojo1.2.0.dev2026092905 /isolatedMAX26.7.0.dev2026092905 unchanged. Minimum available memory111.477GiB; final113.554GiB; reserve32GiB. One execution slot, one-thread builds, one-CPU precompile, finite180s build/30s native guards. Two64-Float64 trial buffers add1,024 explicit bytes. No dependencies/driver/power/security/profiling permissions/default/precision changes; H3paused; no counter retry; dynamic spills/stalls unmeasured.

Connection checkpoint: one initial process-creation transport error started no job/file; harmless checks confirmed that before retry. All11 subsequent owned stages passed. No duplicate commands or ongoing blocker.

Sealed checkpoint: GPU idle, no owned jobs. Review equations/domain before any full temporal-friction integration; no broader solver or benchmark is implemented. Evidence: analysis.json, verification.json, predeclared.json, raw source/package cases, primary sources, package/dependency and executable fingerprints, telemetry and FINAL-SHA256SUMS.
