# Fixed-active unique-contact advance: concrete proposed contract

Recommendation: implement a narrowly qualified, empirical-accuracy Dormand–Prince fifth-order method with step doubling and conservative analytic event bounds. Do not claim a rigorous global ODE error enclosure. This replaces an unnecessarily strong *unimplemented proposal requirement*, not an approved accuracy gate. All existing physical validation gates remain. A formal all-state proof would require the validated Taylor alternative described below.

This document supersedes the unspecified numerical choices in the sealed FINITE-TIME-DESIGN.md; that original remains unchanged. No GPU or production advance has been implemented.

## 1. Physics and orientation

Same domain: one box/unique vertex, spherical inertia I, fixed horizontal floor, zero friction/restitution/external torque, constant external force/gravity. One active feature throughout the requested macro, no impacts or transitions. Preserve every existing body/shape/force limit. Let a_e=F/m+gravity, r=R c, n=(0,1,0). The general world-inertia equations remain the physical definition; spherical inertia and zero torque give the exact specialization

    x'=v; Q'=0.5*(omega,0)⊗Q
    K=1/m+(r_x²+r_z²)/I
    q=a_e,y+[omega×(omega×r)]_y
    N=-q/K
    v'=a_e+N*n/m
    omega'=(r×N*n)/I.

The fixed positive branch requires N>0; never clamp negative N to zero to continue it. Production should compare any algebraic specialization with the unchanged qualified query on admissible states. No fixed-arm or fixed-pressure approximation is permitted. R, r, K, N and omega are refreshed at every stage.

Q is stored in (x,y,z,w) order and integrated as four ordinary coupled components. Evaluate geometry using Q/||Q||, matching existing rotation semantics; never overwrite the integrated quaternion with this normalized evaluation copy. Entry and accepted endpoint quaternion norm² must satisfy the original1e-10 gate. No pose/velocity projection or Baumgarte stabilization.

RK intermediate stages are private algebraic evaluations, not admitted physical states. They can have O(h²) contact residuals despite an accurate endpoint. Therefore use a separate smooth RHS helper with the same reaction algebra, finite/profile checks and positive-N branch; do not weaken or edit the qualified query's public geometry/normal-speed admission gates to make it accept stage states. The RHS extension off the constraint surface is a numerical stage construction, not permission to publish an off-contact support state. Physical entry, half-step and accepted endpoints retain the original admission checks.

## 2. Concrete integration and quadrature

Use the standard seven-stage Dormand–Prince fifth-order formula; the exact tableau is included in prototype.py (A and B). The fourth-order embedded formula is not the acceptance oracle. For each trial h compute one full fifth-order step and two fifth-order half steps from the same entry. Accept the two-half-step state, without Richardson extrapolation. The step-doubling truncation estimate is

    e_i = 8*|Y_two_half,i - Y_full,i|/31.

The factor31 follows fifth-order global accuracy;8 is an explicit safety factor, not a proof. Each trial uses at most21 RHS evaluations, without relying on FSAL. Evaluate errors both on state and on the observables below. Reject/split on any nonfinite quantity, profile failure, bad physical checkpoint, failed event bound or exhausted error allowance.

Integrate in the same RK stages/weights:

    J_n'=N
    M'=r×N*n                  (three COM angular-impulse components)
    W_c'=N*v_n.

If fixed-origin angular impulse is needed, add its three components with derivative (x+r)×N*n; do not substitute a frozen lever arm. External work is computed independently as m*a_e·(x_end-x_entry). These are support ledgers, never impact/restitution history. The initial ledgers are zero; partial attempts cannot mutate them.

## 3. Accuracy budgets and what they mean

Unchanged final gates: the existing scaled1e-10 full-state and momentum comparisons; quaternion norm² error<=1e-10; existing orientation/basis gates; active gap and speed bands1e-9; energy gate B_E=1e-9*(1+T_entry). Preserve the original macro and later one-second accuracy tests. No old planar-slop exception is imported.

The following are *internal numerical allocations*, not relaxed public tolerances. For state components use B_i=1e-10*(1+min(|Y_entry,i|,|Y_candidate,i|)); retain the smallest scale encountered during the macro. If a budget shrinks, recheck all accumulated estimates. Independent final comparison still uses the original reference-based scale, exactly. For orientation additionally check the physical rotated basis, so quaternion sign/scaling cannot hide orientation error.

For active geometry, outward-evaluate input gap/speed intervals G0 and V0. Before starting, reserve their actual propagated residual:

    gap_room = 1e-9 - sup_{t∈[0,H]} |G0+t*V0|
    speed_room = 1e-9 - sup |V0|.

Use these remaining rooms as B_g/B_v; nonpositive room rejects except the exact analytic neutral branch. No residual is reset. For each observable budget allocate at most50% to the sum of step-doubling estimates,25% to a Float64 noise allowance, and25% to independent-reference uncertainty during qualification. For an accepted segment h, its truncation/noise allowance is proportional to h/H. Sum absolute estimates with compensated summation; never reset at a base boundary. Apply the same scheme to active gap/speed observables and the momentum/energy/work ledgers, not only raw position.

A concrete noise guard is64*machine_epsilon*(1+maximum absolute stage/checkpoint observable) per accepted segment. It is a noise floor for admission, **not** a proven accumulated roundoff bound. Maintain explicit cumulative arrays E_new=E_old+e_trial and R_new=R_old+noise_trial for every state/observable; rejected trials add nothing. Both full and half paths start from the same current committed-in-trial state. Do not describe this sum as a bound on nonlinear amplification. Also monitor the actual checkpoint gap/speed departures from g_entry+t*v_n,entry and v_n,entry; these departures must fit the remaining active-geometry budget. These accumulated estimates and their safety factor do not prove nonlinear global error. Qualification must verify the actual endpoint and consecutive-step errors against the independent oracle. Restrict any promotion to the tested domain; do not call it an all-state certificate.

Momentum budgets use the unchanged scaled gates on the actual integrated external/support impulse and moment, with the same50/25/25 allocation. Check vector norms, not just individual components. Error-check J_n, M and optional origin ledger against the independent oracle as well; algebraic agreement between a velocity update and its identically weighted impulse ledger alone is insufficient.

Energy needs both independent residuals:

    |ΔT-W_external-W_c| <= B_E        (bookkeeping)
    |ΔT-W_external| <= B_E            (ideal frictionless-support energy).

The second prevents numerical contact work from excusing a physical energy error. For energy use remaining room E_room=B_E-|W_c|, shrinking it and rechecking cumulative estimates whenever |W_c| grows. Nonpositive room rejects. Allocate50% of E_room to estimated integration/quadrature error,25% to noise and25% to reference uncertainty. Charge actual contact-work drift separately: require |W_c| plus the actual accumulated bookkeeping-error estimates, noise allowances and reference uncertainty<=B_E. If this fails, split or reject; never set W_c=0. This can reject an otherwise instantaneously admitted near-zero-speed state. No extra dissipation or impulse loss is introduced.

The50/25/25 split is an implementation budget choice, not evidence that the error estimate is a rigorous bound. If tests show this estimator misses a gate, stop and diagnose; do not widen the gate or silently retune it.

## 4. Conservative event bounds, without an interval ODE solver

The following inequalities are analytic for the exact local IVP in this spherical-inertia/zero-torque domain. Use outward-rounded interval arithmetic for their input quantities and scalar evaluations in production. The CPU prototype currently evaluates them in ordinary Float64 and is not a certification implementation.

Let R_s=|c_selected|, W0=|omega_entry|. Choose

    W = min(sqrt(300), W0+max(1,W0/2))
    N_max = m*(|a_e,y|+W²*R_s)
    A_omega = R_s*N_max/I.

Require W0+h*A_omega<=W; otherwise halve. This bootstrap bounds the angular norm by a first-exit argument. Also check the original component-wise angular/linear/position profiles with corresponding derivative enclosures; the scalar W does not replace those public limits.

For q, a bound on its derivative is

    Qdot_max = R_s*(2*W*A_omega+W³).

Require upper(q_entry)+h*Qdot_max<0. Since K>=1/m>0, this excludes reaction zero/unloading throughout the interval. K need not have a new conditioning threshold. No positive margin beyond the rounding/error enclosure is invented.

For every inactive corner j, R_j=|c_j| and

    A_j=|a_e,y|+N_max/m+A_omega*R_j+W²*R_j.

A whole-interval gap lower bound is

    min(lower(g_j0), lower(g_j0+v_j0*h)-0.5*A_j*h²).

Require it>1e-9 m after accounting for carried state/geometry uncertainty. This catches possible between-sample contacts conservatively. Inconclusive bounds cause subdivision or rejection; the first version never steps through unloading or new contact and does not need to locate their event times. For the active feature, exact g''=0 gives G0+t*V0; add the accumulated numerical gap/speed allowance and recheck the existing bands at every physical checkpoint.

Important distinction: outward event inequalities can certify the exact *local* IVP given an enclosing input state. A carried state-error radius derived only from step doubling is empirical. Therefore the combined whole-macro result is not a formal global enclosure. Independent geometry refinement validates it in the qualified cases. If a formal global guarantee is required, use the Taylor alternative instead.

## 5. Finite work bounds and neutral handling

0<H<=1/30 s; four fixed H/4 bases. Begin each base with one full-base trial. On failure, split that pending interval into equal halves; process left then right, with no step growth or discarded remainder. At most6 accepted segments and12 attempted trials per base:24 accepted,48 attempted per macro, at most1,008 RHS evaluations. Failed geometry/bootstrap/error trials count against the attempted limit. Split underflow or a nonpositive/unrepresentable remainder rejects. Each attempt uses one analytic whole-interval event-bound evaluation; this stays below the prior proposed64-refinement ceiling and does not introduce an additional search loop. Checkpoints are bounded by the21 stages plus full/half endpoints.

Neutral N=0 is a separate exact-polynomial branch, only for the already qualified sufficient certificate: omega=0, v_y=0, F_y=0, gravity_y=0, unique current geometry and computed N=q=0. Then R/omega and vertical position/velocity remain unchanged by the equations, x_t=x_t0+v_t0 H+0.5*a_t H², v_t=v_t0+a_t H; J_n=M=W_c=0. This is an analytic solution, not clamping nonzero motion. Check world/profile bounds and energy, preserve the initial gap residual, and consume exactly H on success. Near-zero or cancellation-based cases without this certificate remain unsupported. N=0 with positive opening acceleration is not sustained contact: route to a later flight owner or reject this advance, never keep it on the support branch.

Whole-macro atomic rollback covers body, force, identity, elapsed time, all ledgers and episode history. Commit/consume forces only after all bases and final physical gates pass. Identity changes, events, numerical uncertainty and cap exhaustion all leave entry bytes untouched. No impact counter is incremented.

## 6. Independent reference and first test

Use Decimal80 classical RK4 with a nine-component rotation matrix R'= [omega]×R, not the production quaternion DP tableau. Use direct scalar spherical inertia and independent geometry/force evaluation. No rotation-matrix reorthogonalization. Compare64/128/256 equal panels; require refinement ratios in[8,32] for nonzero dominant differences and an uncertainty estimate8*|Y256-Y128|/15 below the reserved25% budget for every observable. For exact analytic controls, zero differences are valid. Check50-vs80-digit runs separately; precision error must be below the same allowance. If insufficient, double up to4,096 panels with finite CPU deadline; no convergence means no qualification. Record orthogonality error and recover the quaternion with the initial sign/norm convention only for reference comparison. Verify independent analytic static/neutral controls and momentum/work invariants as well as convergence.

First tiny rocking test: saved prototype fixture, mass2, spherical inertia4/3, half-extents(.5,.5,.5), body Euler(.4,.2,-.3), shape Euler(.1,0,.07), gravity(0,-9.81,0), omega(.2,.1,-.15), tangential COM velocity(.3,.4). Set COM height and normal velocity analytically for the unique lowest feature, retain Float64 representation residuals, H=1/3000 s. This has genuine nonzero angular acceleration. Then test all profile/geometry/identity boundary rejections and short consecutive intervals before expanding H or claiming one-second coverage.

CPU feasibility result: four accepted segments/four attempts,84 DP RHS calls; max error vs Decimal80 matrix RK4≈1.175e-16; reference refinement ratio≈15.999994;50/80 precision difference≈7.126e-49. Angular velocity changed≈1.519e-3 rad/s, active gap≈1.110e-16 m, energy/work residual≈4.307e-16 J. No projection. This is one feasibility sample, not a production qualification or all-interval proof.

## 7. Certification alternative and recommendation

Practical DP5: scalar/vector arithmetic,21 RHS evaluations/trial, cheap analytic geometric bounds and adaptive binary subdivision. It fits the tiny test with substantial accuracy margin. Its truncation/noise control is empirical; rigorous event inequalities do not turn its global error estimate into proof.

Rigorous alternative: eighth-order interval Taylor integration with outward-rounded coefficient arithmetic, Picard/self-inclusion bounds for the state tube, interval ninth-derivative remainder, quaternion/geometry and ledger enclosures. Reuse the same physical tolerances and outer segment/attempt caps. It requires interval transcendental/square-root handling, rational reaction denominator bounds, coefficient recurrences and dependency control. Runtime/memory would be substantially higher and less predictable; no measured cost or feasibility within24 segments is claimed. Failure to obtain self-inclusion within the cap must reject. This provides a route to actual whole-interval/global proof, unlike step doubling.

Recommend the practical scheme for the first tiny empirical correctness qualification, explicitly labeled as such. Requiring full proof would be a separate verification requirement beyond the already approved empirical/reference accuracy gates. Neither scheme changes the force model or relaxes those gates. Do not promote a general finite-time guarantee from this CPU demonstration.
