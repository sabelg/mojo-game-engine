# Isolated rotating single-vertex floor impact prerequisite

Selected prerequisite: refreshed rotated box geometry and a frictionless instantaneous single-vertex normal impact. No advance owner, trajectory integration, TOI solver, multibody behavior, warm seed, packing, timing or default promotion is included. The straight-sliding owners and their receipts remain immutable.

Existing flat-face `certified_face` samples only four local bottom corners. `frozen_floor_friction` requires identity body orientation and near-zero free angular velocity, and its pressure redistribution solves a zero-net-torque flat translation. It cannot represent genuine tipping or rotating contact. Existing general box geometry (`prepare_bounds`, SAT/clipped patches) handles rotated shapes for endpoint response, but it does not supply rotating continuous floor TOI. Existing `BodyState.integrate` carries world angular momentum, reconstructs orientation-dependent inertia, uses a bounded implicit midpoint angular solve and quaternion exponential; it does not justify replacing a rotating support height with the COM quadratic root. This experiment does not alter either code path.

## Geometry and physical law

At the actual supplied pose, refresh all eight vertices:

    r_i = R_body (center_local + R_shape corner_i)
    p_i = COM + r_i
    gap_i = p_i.y - floor_y
    u_i = v_COM + omega x r_i

Select the unique lowest canonical vertex, independent of cyclic/reversed enumeration. Use the actual material vertex arm, with no midpoint contact projection, no pose correction, and no restriction to the old local bottom face. Its gap must be within the existing1e-9m geometry certificate and all other vertices must be outside that band. Edge/face ties and penetrated/separated poses are rejected. The floor is an infinite fixed horizontal plane; finite-footprint admission remains future work.

Compute the complete3x3 world point-velocity effective mass:

    K_ab = delta_ab/m + (r x axis_a) dot I_world^-1(r x axis_b)
    I_world = R_body diag(I_body) R_body^T

The contact metric is positive definite for positive mass/inertia; this is not a claim about a nonlinear friction Jacobian. Normal/tangential and angular coupling are retained, including nonzero off-diagonal entries and induced yaw velocity under anisotropic inertia. For n=(0,1,0), incoming normal point velocity u_n, a caller-certified new impact uses beta=-e*u_n only when u_n<-.2m/s; otherwise beta=0. Continuing contact always uses beta=0. A separating row receives zero impulse. A closing row gets lambda=(beta-u_n)/K_nn, J=lambda*n, delta v=J/m, delta omega=I_world^-1(r x J). No component of omega, yaw, tipping or angular momentum is suppressed. Pose, inertia, mass, force and torque are bit-preserved; the primitive is instantaneous and integrates no external forces.

Friction law in this prerequisite is exactly mu=0, tangent impulse0 and zero-radius Coulomb disk. Nonzero friction is rejected. A later rotating friction block must use the complete coupled point metric and a circular maximum-dissipation disk, solve normal/tangent coupling and validate both residuals; the flat-face zero-torque shortcut must not be reused. The normal impulse here is a cold one-shot quantity in kg m/s, not a warm cache or later friction bank.

## Restitution episode contract

The isolated input carries a new-impact boolean. Accepted closing application consumes that designation; the output exposes the frozen target and whether it consumed a new impact. This block has no world identity/episode registry and cannot certify the caller's flag. A future owner must authorize it from body generation, shape generation/revision, the full contact/material feature key and actual separated-to-touching history; quiet persistence or a refreshed iteration must not authorize restitution again. Calls made from the actual accepted output with continuing=false-new input must have beta0, no second bounce target and no additional energy. Before retrying a nonlinear correction, its incoming target must remain frozen while impulse deltas update the current group. Unsupported/rejected calls publish no body changes and consume no episode designation.

## Gates and independent evidence

Preserve the existing1e-10*(1+abs(reference)) state gate, normal1e-9 scaled residual, energy1e-9 scaled gate, profile limits, exact rollback/input/canary checks and geometry1e-9 certificate. No gate relaxation is authorized. Check linear momentum change J; world angular momentum change r x J; angular momentum about a fixed origin change p x J; and no energy creation. Analytic loss for a closing contact is .5*(1-e_eff²)*u_n²/K_nn. Opening contacts preserve all state bits. Forces/torques are unchanged, not consumed by an instantaneous primitive.

A separate standard-library Decimal80 oracle uses explicit quaternion-to-matrix arithmetic, full world inertia matrices and vector products from the exact Float64 input values. It computes geometry, all nine K entries, the analytic impulse, poststate and momentum/energy witnesses without importing production Mojo/core helpers. Native qualification compares to precomputed independent references, stops on its first physical/state/identity failure, and checks complete rollback on every rejection. Source and a fresh minimal package must agree exactly. Four mass/inertia/aspect variants, arbitrary pitch/roll/yaw and inverted poses, angular-only closing/tipping, shape-local rotation/offset, translated floors, new/continuing impacts, e0/.5/1 and threshold/near-zero/opening boundaries are exercised under sixteen vertex enumerations. Explicit rejection cases cover face/edge ties, mu>0, malformed law/shape/profile, separated/overlapped geometry and a post-impulse angular profile overflow.

No trajectory is claimed by this stage. The next prerequisite must refresh all eight gap functions along actual torque-free/forced angular evolution and locate the earliest valid approaching root; a COM quadratic is insufficient. Before a rotating trajectory owner, use an independent high-accuracy Euler/quaternion integration with refinement/convergence and invariant checks (not only a CPU transcription of the same midpoint code), sweep grazing/feature changes and certify nonpenetration/time consumption. Genuine consecutive trajectories, complete energy/angular-momentum/episode rollback and finite-floor admission are required before timing or interacting bodies.

Execution: one GPU slot, single-thread builds, one-CPU fresh package precompile,180s build/30s native guards,>=32GiB available memory, unchanged pinned Mojo1.2.0.dev2026092905 / isolated MAX26.7.0.dev2026092905. H3paused; no system-setting or profiling-permission changes. Stop at the first substantive physical failure or complete bounded correctness result for review.
