# M03 typed curve slice — isolated candidate

M03 is complete for the finite profile documented below. The frozen candidate and
independently compiled 247-file SDK each passed 56 software and 56 GB10 checks.
After promotion, the engine checkout rebuilt successfully and passed another
56 software and 56 GB10 checks. See [roadmap evidence](ROADMAP.md).
The completion update changes documentation only; historical reports keep their
original source identities. General USD animation and production-game workflows
remain outside this qualification.

## Supported channels

`curves(path=..., time=...)` emits one row per scalar/vector/orientation component.
Each row has its original attribute `name`, zero-based `channel`, display `label`,
tuple `width`, USD `type`, sampled scalar `value`, and composed scalar keys.
Float/double scalars, float/double vectors of width two or three (including their
USD roles), and float/double quaternions are supported. Vectors retain precision,
role and sibling components. Orientation components use x,y,z,w and normalize
together. Connected/uniform attributes and instance proxies are read-only.
Time-sample operations on Ts splines reject rather than erase tangent semantics.
Supported scalar splines have separate knot/tangent tools and an explicit bake.

The editor uses E to cycle channels, Enter to enter a channel value, M to enter a
key destination time, V to copy a key to another time, and Delete to delete the
key. G retains source-map selection. **Move/copy/delete affect the whole typed
attribute key**, so vector siblings and quaternion components share that key's
time. Quaternion channel values normalize together. The graph joins authored
component keys with linear guides; its current numeric values use USD sampling.
Curve-shape visualization is still part of the remaining interpolation work.
Fractional stage times are preserved. The version 2 curve IPC includes the
original attribute and channel index separately from its display label.

## API operations

`set_channel(path, name, channel, value, time)` authors one component at a numeric
stage time. Local overrides seed composed endpoint keys before the first edit.
Owned source targets read their own tuple, avoiding stronger composed overrides
when preserving sibling values. If that source has no numeric opinion, select
its contributing mapping or explicitly author a full tuple with `attribute`.

`copy_key(path, name, from_time, time)` and `move_key(...)` copy/move a whole tuple
from a key in the selected layer. Existing destination keys reject the operation.
Local targets first seed the composed numeric curve if they have no sample map.
`clear_sample` deletes a whole tuple key. All operations participate in atomic
rollback and undo/redo. Mapped source paths and layer-time offsets/scales apply to
both ends of a key operation. Stronger-layer masking reports feedback.

Direct typed `attribute` edits also accept vectors and orientations. Editing the
existing translate/rotate/scale/orient attributes preserves `xformOpOrder`, pivots,
inverse operations and reset-stack metadata. The older matrix `transform` command
retains its explicit transform-stack replacement behavior.

## Evidence and remaining work

`tests/usd_typed_curves.py` validates fractional tuple operations, double precision,
mapped references, stronger-layer masks, pivots and reset stacks, Euler/scale and
quaternion interpolation, rejection rollback, undo and workspace/USD/USDZ restart.
`tests/usd_typed_editor.py` exercises the actual IPC bridge across restart.
`tests/usd_spline_rejection.py` generates a real pinned-OpenUSD spline and verifies
that its tangent semantics remain intact. `--smoke-channels` exercises the native
window on software Vulkan without launching a preview cook.

## Scalar spline tools and explicit baking

`set_interpolation(path,name,mode)` converts selected-layer scalar time samples
to a USD Ts spline or changes an owned spline's modes. Modes are `held`, `linear`
and `bezier`. New Bezier tangents start flat with one-third segment widths.
`set_spline` accepts increasing knot times/values/modes and manual in/out slopes
and widths. `set_tangent(path,name,time,side,slope,width)` edits a knot using
stage-time units, translating widths and slopes into mapped-layer units.
`spline` inspects the selected opinion. `set_spline_value`, `copy_spline_key`,
`move_spline_key` and `delete_spline_key` preserve typed knot values and tangents;
invalid destination collisions or crossed tangent widths reject atomically.

The profile is float/double scalar, non-looping Bezier-form splines with manual
tangents and no dual or time-valued values. Unsupported layouts reject explicitly.
USD/USDZ and workspaces preserve splines. Animated runtime preview requires an
explicit bake first; a static disposable preview samples its requested time.

`bake_curve(path,name,start,end,step,max_error)` replaces the selected spline with
typed linear samples over the explicit range. It includes interior knots, refines
quarter/midpoint errors, then validates 31 interior positions per resulting
segment. Limits are 10000 keys and 200000 evaluations. This is a finite sampled
error contract, not a proof of continuous error bounds. Discontinuous held curves
reject linear baking. Undo restores the spline. Independent analytic tests check
1001 positions for the tested Bezier fixture.

The editor provides O to cycle held/linear/Bezier, D/F for outgoing/incoming
tangent input (`slope,width`), F1 for a new rate, and F2 for explicit bake input
(`start,end,step,error`). Existing spline value/move/copy/delete controls operate
on knots. The displayed graph remains key guides; it does not plot an exact spline.

## Physical retiming and named deformation channels

`convert_frame_rate(rate)` requires owned copies of the complete source graph and
resolved source conflicts. It scales all owned sample/knot times, manual tangent
widths and slopes, timeline bounds, and sublayer/reference/payload offsets while
preserving seconds. It updates layer frame/time-code rates and refreshes mapped
targets. Mixed explicitly authored rates, clips, time-valued values, unsupported
splines and exceeded spec/sample budgets reject atomically. Existing timeline
metadata editing remains distinct from physical retiming.

SkelAnimation translations (float3 arrays), rotations (quatf arrays), scales
(half3 arrays) and blendShapeWeights (float arrays) expose named flattened channels.
Each array contains 1..64 entries matching its uniform joint/blend-shape name list.
Editing preserves sibling joints and channels; rotations slerp and normalize per
joint. Half precision overflow and array/name mismatches reject. Copy/move/delete
affect the entire attribute array key. Binding/topology edits are outside this
authoring slice. Inspector limits are 1024 channels and 100000 channel keys.

## Additional evidence and remaining acceptance

`usd_animation_authoring.py` checks analytic held/Bezier evaluation, tangents,
bake error, mapped physical retiming and persistence. `usd_animation_editor.py`
checks the actual IPC controls and author clock. `usd_skel_authoring.py` checks
edited poses and morph weights with an independent native USD Skel evaluator at
keys and between keys. Four software-rendered native spline camera samples match
independent analytic lens projections pixel-for-pixel (`usd_animation_render`).

`usd_animation_latency.py` measures 36 animated cameras and 128 transform prims,
without meshes: median edit 4.1 ms and edit-to-READY 385.5 ms in the recorded run,
including the preview debounce. Camera/light companions survive empty-geometry
publication and only the latest queued revision is published. This excludes mesh
cooking, GPU upload, representative rig/mesh preview and general latency budgets.

The disposable Blender conversion now uses a bounded integer grid which retains
fractional authored keys (smallest factor 1..64). It samples at most 10001 frames
per varying attribute, 200000 attribute evaluations and two million array values;
serialized conversion stages remain below 64 MiB. Blender conversion frames must
lie in [0,1048574]; unsupported finer grids and time-valued attributes reject.
The worker sets an explicit frame rate/base to retain physical seconds. Camera and
light companions also retain fractional keys from their animated ancestors.
`usd_fractional_sampling.py` compares original and converted native USD Skel poses;
`usd_fractional_playback.py` cooks actual skin/morph data and supplies seven
independent USD reference poses for runtime numerical and image comparisons.

`usd_animation_workload.py` covers a synthetic fixture with 10000 source vertices,
19602 triangles, 32 authored joints, two morphs and an animated camera. Three edits
and cancellation of an active cook must publish the current revision, leave the
source unchanged, reach READY within 30 seconds each, stay below 768 MiB sampled
owned cook-process RSS and publish below 64 MiB. The initial median was 2.43 seconds
and sampled peak 382 MiB. The runtime test uploads/deforms/draws/captures four poses
within 15 seconds, checks reversible seeking, changing nonblank images and zero
Vulkan validation errors. These are explicit finite acceptance bounds for this
fixture, not production-art or overnight performance claims.

Blender's restricted shutdown hang was traced to OpenAL's backend initialization.
Only the disposable headless conversion worker sets `ALSOFT_DRIVERS=null` and dummy
SDL audio, with `-setaudio None`; normal authoring and user preferences are intact.
The backend setting is documented by
[OpenAL Soft](https://github.com/kcat/openal-soft/blob/master/docs/env-vars.txt).

The promoted finite profile retains its exact qualification, independent SDK and
rollback evidence in `build/roadmap-m03/root-promotion-acceptance.json`.
