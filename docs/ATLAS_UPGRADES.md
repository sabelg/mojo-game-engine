# Atlas world-development upgrades

Atlas now connects asynchronous terrain/cell streaming, instanced scene rendering,
stable asset references, partition authoring, capsule movement and skeletal clips.
These are working engine systems with regression tests, not a claim of complete
production-engine or glTF conformance.

## Run and author

### USD production authoring

Atlas has a native OpenUSD 26.03 authoring service and an offline geometry bridge
through locally compiled Blender 5.2.2. The game runtime consumes native Atlas
assets; it does not load Blender or OpenUSD. The implemented compatibility profile
is deliberately finite. **The full USD roadmap is not complete.**

```sh
# Ubuntu ARM64 bootstrap; needs git-lfs, CMake, desktop development headers,
# base C/C++ development tools and CUDA 13. Installs under .deps.
pixi run usd-setup
pixi run usd-test           # builds Atlas, runs declared profile + software Vulkan
pixi run usd-test-hardware  # same profile with the hardware Vulkan driver
pixi run blender

pixi run python scripts/cook-assets.py assets/usd/scene.usda \
  --output build/usd-cooked --id scene
pixi run python scripts/atlas-project.py import --project /path/to/world \
  --source /path/to/art/world.usdc --usd-root /path/to/art --id district
```

The cooker accepts `.usd`, `.usda` and `.usdc`. `--usd-root` specifies the common
asset directory for shared references/textures; by default it is the source's
parent. Dependencies outside that root are rejected. Limits remain 64 MiB/file,
256 MiB/bundle, 4,096 dependencies and 250,000 vertices/primitive. The conversion
cache hashes source dependencies, the actual converter binaries and adapter code.
Rejected imports preserve the active manifest and previous immutable generations.

Set `ATLAS_BLENDER`, `ATLAS_USD_INSPECT` and `ATLAS_USD_STAGE` for external tools.
SDK version 26.03 is pinned to Blender's ARM64 dependency package. It is not a
claim to support every OpenUSD release or third-party schema.

#### Native authoring and delivery

`scripts/usd-session.py` provides `StageSession` and `BackgroundStageSession`.
They keep an actual native `UsdStage` alive, open with payloads unloaded, and place
edits in a separate session layer or a selected local override layer. Supported operations are `open`, `snapshot`,
`variant`, `transform`, `attribute`, `visibility`, `active`, `load`, `unload`,
`reload`, `reset`, `assign_ids`, `repair_ids`, `undo`, `redo`, `timeline`,
`create_layer`, `select_layer`, `clear_layer`, `clear_sample`, `curves`, `save_workspace`, `open_workspace`, `save`, `flatten`, `preview` and `package`. JSON snapshots expose layer
identifiers, variant choices, prim paths, instance prototypes, transforms,
camera/light attributes, composed visibility, identity issues and revision numbers.
Prim paths identify API targets; authored `atlas:uuid` values provide persistent
identity when retained through namespace edits.

```sh
# Inspect a stage without loading payloads:
pixi run usd-stage assets/usd/scene.usda

# Run a JSON array of operations against a persistent stage:
# [{"op":"variant","path":"/World/Placed","set":"size","value":"small"}]
pixi run usd-stage assets/usd/scene.usda --commands edits.json

# Save an override layer, or a self-contained USDZ delivery:
pixi run python scripts/atlas-project.py usd-author --project /path/to/world \
  --source /path/to/art/world.usda --commands edits.json \
  --destination /path/to/art/world-edited.usda
pixi run python scripts/atlas-project.py usd-package --project /path/to/world \
  --source /path/to/art/world-edited.usda --destination /path/to/art/delivery.usdz
```

Export parents must exist and destinations must be new. `save` retains the source
as a relative sublayer, copies stage metadata and writes only overriding opinions.
`package` collects dependencies and writes a portable USDZ without modifying the
source. `flatten` requires every payload to be loaded so it cannot silently omit
unloaded content. Failed edits restore all local layers, the edit target and payload rules; source reload
errors require correcting the source and retrying reload. Matrix edits replace
the selected prim's local transform stack in the override; they do not rewrite
its original animation channels. Transform, visibility and supported generic
attribute edits accept optional numeric `time` in USD time codes; omitting it
authors a default opinion. Numeric values interpolate according to USD semantics;
visibility tokens use held interpolation. Uniform attributes reject time samples.
The first time-sampled attribute/visibility edit copies the composed sample map
into the selected authoring layer, preserving other keys despite USD layer-strength rules.
Those copied keys then override later weaker-layer changes until cleared/reset.
`clear_sample` removes only an existing sample in the selected layer at the requested time;
it cannot delete source-layer keys. `timeline` sets `start`, `end` and
`time_codes_per_second`, with ordered endpoints within +/-1e9 and a rate in
(0,1000]. These operations participate in undo/redo and preserve their opinions
through override save, flatten and portable USDZ delivery. The API validates the
authored sample; it does not certify every interpolated pose between samples.

Local authoring layers: `create_layer` with an ASCII `name` creates and selects
one of up to eight owned anonymous layers. The session layer is strongest; newer
local layers are inserted above older ones, with the source beneath them all.
`select_layer` accepts `session` or an existing local name. `clear_layer` clears
only the selected target; `reset` clears all local edits and returns to session.
Creation, selection and clearing are undoable. Reload retains every local layer.
Timeline metadata requires the session target. A stronger opinion can mask an
edit in a weaker target: selection does not change layer strength.

In the native window, B creates a layer, T cycles editable targets and X clears
the current layer (undo with Z). The sidebar shows the current target. Layers
created by the window receive automatic names; API callers can choose names.
`curves` reports `authored_in_target` per composed key and `edit_target`.
The legacy `session` flag continues to indicate a sample in the session layer.

Save and package collapse the owned local stack into one override layer while
retaining source composition and time-sample strength. The composed result
survives reopening, but delivery exports do not retain local names and separate
edit targets. Use `save_workspace`/`open_workspace` to preserve the named layer
stack, selected target and payload rules across restart. The native editor uses S
for workspace save, F9 for reopen, F6 for USD delivery and P for USDZ. Its status
line indicates unsaved workspace changes. See [workspace format and recovery](USD_WORKSPACES.md).
Owned filesystem source/reference editing is implemented for M02 with targeted checks; complete software/GB10 qualification remains pending. Layer reordering remains outside this scope. See [source-copy mappings and conflict resolution](USD_WORKSPACES.md#owned-source-editing-m02).
History restarts empty after workspace open and is bounded to 32 entries and 64 MiB per stack;
the combined current local layers must fit within 32 MiB.

Snapshots report invalid IDs and duplicate ID groups. `repair_ids` (C in the native
USD window) assigns missing/invalid IDs and replaces duplicate occurrences, keeping
the lexically first concrete prim for each valid ID. It leaves unique valid IDs and
source files intact. Repeating repair is a no-op; undo restores all prior IDs. The
scope is loaded concrete prims, including reused references and native instance
roots; abstract prototype templates are excluded. Unloaded payload contents and
instance-proxy descendants require separate reconciliation. Repair can invalidate
external links to a replaced duplicate ID; the original and repaired mappings
remain available in snapshots and undo history. No repair occurs automatically.

```json
[
  {"op":"repair_ids"},
  {"op":"timeline","start":0,"end":24,"time_codes_per_second":24},
  {"op":"attribute","path":"/Camera","name":"focalLength","value":40,"time":0},
  {"op":"attribute","path":"/Camera","name":"focalLength","value":80,"time":24}
]
```

The service limits loaded prims to 100,000 (configurable downward), JSON requests
to 1 MiB and nesting to 32. The Python client defaults to a 60-second operation
timeout, four USD worker threads and a 4 GiB process virtual-address limit through
Linux `prlimit`. A timed-out process must be reopened. Background operations use
one serial worker, eight queued requests by default and cancellable queued futures.
These are authoring safeguards, **not** GPU-world streaming or frame-time guarantees.
`WatchedStageSession` reloads changed layer files while preserving session overrides,
reports invalid edits, and recovers when the source is corrected. Texture changes do
not trigger GPU publication. `pixi run usd-editor --source /path/to/stage.usda`
opens the native prim/layer/variant window; F11 opens it from the world editor.
Use Z/Y for session undo/redo, arrows to select prims/variant choices, Tab to select a variant set, L/U for
payloads, R to reload, I to assign persistent IDs, C to repair conflicts, S to save a workspace, F9 to reopen it, F6 to export a new override layer,
and P to package USDZ. W creates source copies, G cycles mapped source targets, F7 keeps edited copies after a source conflict and F8 reloads source copies (undo with Z). Original source files remain read-only.

The integrated 3D viewport updates after edits and layer reloads by cooking a
disposable copy of loaded content in a separate process. Space plays/pauses, `[`/`]`
step one source frame and Home seeks to the beginning. K toggles authored versus
inspection camera, N cycles authored cameras and J toggles authored lighting.
Right-drag or wheel over the view to orbit/zoom in inspection camera mode. Authored
camera aspect is preserved with letterboxing, including exposure and lens animation.

Node TRS, skeletal poses, morph weights, composed visibility and supported
camera/light tracks share a zero-based clock. Blender scene exports are shifted to
the stage start so a nonzero source start frame does not offset character motion
from camera or lighting. The cooker's `*-playback.atlasplayback` binds scene clips,
skins, skeletons and morph meshes; `PreviewPlayback` merges disjoint USD scene clip
channels and rejects overlaps. Ordinary glTF playback metadata selects its first
clip. CPU skin/morph inspection is bounded to 250000 deforming vertices; seeking
updates GPU meshes and culling bounds. GPU morph computation and production crowd
performance are not established by this path.

Empty loaded stages correctly clear the view. Unsupported content reports a
preview error. The `preview` API operation writes a disposable USD copy and reports
its revision. Its default is a static time sample; `animated: true` preserves the
loaded stage's animation. Unlike delivery `flatten`, both intentionally omit
unloaded payload contents. Existing-layer edit-target selection, vector/transform curve editing, tangent
handles and unsupported renderer features remain outside the viewport profile.

The viewport's scalar keyframe panel inspects the selected prim. Pause playback,
use E to cycle editable float/double properties, press Enter to type a finite value,
and Enter again to set a key at the nearest source frame. Escape cancels entry;
Backspace edits it. Delete removes a key authored in the selected layer at that frame. Z/Y undo
and redo these edits. Source files are never changed. Keys present in the selected target are orange; other composed keys are grey; the graph shows USD's linear interpolation. Curves with more
than 256 keys are downsampled for drawing only. Inspection is bounded to 256 scalar
properties, 10000 keys per property and 100000 keys total. Uniform and connected
attributes are read-only. Numeric fields, rather than draggable tangents or handles,
are the supported editing interface. Clearing the last stronger-layer sample can
reveal the underlying source curve again, following normal USD composition.

A newer revision cancels the previous cook process group. Publication requires a
matching current revision and validated runtime assets; failed cooking retains the
last working view and displays its revision. GPU upload is synchronous at the
publication boundary and can briefly stall a frame. Preview jobs time out after
180 seconds, retain at most four unacknowledged generations, and remove their owned
cache/files on close; the last displayed assets stay resident until replacement.
These bounds do not establish a game-world streaming frame-time or GPU-memory
guarantee. Assigned `atlas:uuid`
custom data survives namespace changes when retained by the editing tool; automatic
conflict resolution for repeated assets remains open. Undo/redo restores session
opinions and payload load rules, retains at most 32 steps and 64 MiB of serialized
opinions per stack, and rejects sessions above 32 MiB. Failed edits/open operations
preserve history. A new edit after undo clears redo; successful external reload
clears both history stacks while retaining current session overrides.

#### Camera and light runtime samples

Cooking emits optional `*-cameras.atlascameras` and `*-lights.atlaslights` files
inside the immutable generation, alongside the source provenance report. Samples
are evaluated at the stage start time. `AuthoredCamera3D` loads named perspective
or orthographic cameras, including aperture offsets, clipping ranges and stage
unit/up-axis conversion. Its `view_projection(origin)` supports floating origins.
Use the authored aspect ratio or letterbox the viewport. `AuthoredCameraTrack3D`
loads frame-sampled camera animation, including ancestor motion and focal/aperture
changes. Pose and projection interpolation between samples is an approximation;
animated scale/shear/reflection and projection-type switches are rejected. Physical exposure uses OpenUSD's `ComputeLinearExposureScale()` with
`exposure`, `exposure:iso`, `exposure:time`, `exposure:fStop` and
`exposure:responsivity`. `camera.exposure` is a linear brightness multiplier;
pass it to `AuthoredLighting3D.begin(..., exposure=camera.exposure)`. The inspection
viewer applies it automatically. Exposure values are frame-sampled with linear
interpolation of the resulting scale. Camera formats version 2 retain this value;
version 1 files remain readable with exposure 1. Invalid parameters and scales
outside 0..1,000,000 are rejected. Depth of field, motion blur and extra clipping
planes remain outside this loader. Exposure f-stop is distinct from the USD
`fStop` attribute used for depth of field.

`AuthoredLighting3D` loads one distant light plus constant untextured dome lights.
It applies intensity, exposure and OpenUSD blackbody color temperature. Distant
lights use normal-incidence illuminance with a directional approximation; finite
source shape and angular shadow softness are not reproduced. Dome radiance feeds
Atlas's existing low-frequency spherical harmonics. `AuthoredLightTrack3D` adds
frame-sampled distant/dome animation. `LocalLight3D` supports up to 32 unshadowed
inverse-square point/spot lights. The USD bridge accepts static SphereLights with
`treatAsPoint=true`, isotropic scale and optional smooth cone shaping; this is a
far-field approximation, not finite sphere lighting. Light linking, area lights,
textured domes, connected light graphs and independent diffuse/specular gains
remain authoring-only and are listed in the provenance report. Multiple
runtime distant lights are rejected by the loader. The caller supplies shadows.

`examples/usd_scene.mojo` displays cooked geometry with animated camera/distant/dome
tracks and static local lights. It does not animate rigs or submit shadow geometry. After cooking a source with a camera:

```sh
pixi run usd-view --prefix /path/to/cooked/asset-id --camera 0
```

#### Materials, geometry and animation

The existing Preview Surface path remains. Two additional **constant opaque
metallic/roughness approximation** profiles accept USD shaders named
`ND_standard_surface_surfaceshader` (MaterialX Standard Surface 1.0.1) and
`ND_open_pbr_surface_surfaceshader` (OpenPBR 1.1). Base color, metalness and specular
roughness map to Preview Surface; other authored inputs must match the pinned
MaterialX defaults. Connected/animated inputs and unsupported layers/effects are rejected. This is not a MaterialX graph
compiler or a pixel-identical OpenPBR renderer. Defaults, including inherited
Standard Surface inputs, are recorded in `assets/usd/material-profile.json`.
Tagged constant color inputs use OpenColorIO with the pinned built-in
`ocio://cg-config-v4.0.0_aces-v2.0_ocio-v2.5` configuration, converting to linear
Rec.709. Unknown spaces and out-of-profile output values are rejected. Untagged
colors retain linear Rec.709 semantics. Texture and display color management remain
outside this implementation.

Static subdivision meshes can opt into a bounded bake with
`custom int userProperties:atlas_subdivision_level = 1` (1..3). Catmull-Clark and
bilinear schemes use Blender's subdivision modifier; animated/skinned stages are
rejected for this bake. This is a finite tessellation, not the exact limit surface.
Without the explicit level, subdivision is rejected. Native USD instances are
expanded only in the temporary conversion stage and keep distinct occurrence
paths. Blender can merge a single-mesh parent transform; source prim paths remain
in provenance. This does not preserve native prototype objects in the runtime.

References, selected variants, Preview Surface materials, sampled transform and
skeletal animation, skin weights, source invalidation, HLOD and failure atomicity
retain their regression tests. `MorphTrack` loads `*-animation-N.atlasmorphclip` weight tracks with LINEAR, STEP
and CUBICSPLINE interpolation. Tracks bind to the same stable asset keys as the
mesh manifest. USD blend shapes pass through Blender's source-frame sampling;
glTF cubic tangents are retained. Apply sampled weights through
`Mesh.deform_morph()` before skinning, then submit through `Graphics3D.update_mesh()`
or `Assets3D.replace_mesh()` (which refreshes bounds and retires old handles).
This is CPU deformation with GPU publication, not GPU morph computation. Animated
shape deltas and in-between shapes remain unsupported. Clips are bounded to 64
weights, 10,000 keys per track, 100,000 keys total and 32 MiB.

`VisibilityTrack` loads `*-visibility.atlasvisibility`. It retains composed mesh
visibility from ancestor and mesh opinions at their exact authored time boundaries,
including fractional frames. `VisibilityTrack.hidden(tracks,time)` supplies the
`hidden=` argument on either `Assets3D.draw()` or `draw_cached()`. The same mask can
be passed for shadow submission. It filters asset keys without mutating scene-node
activity. The USD inspection viewer applies these tracks automatically. Geometry
hidden at the first frame is retained during conversion. Visibility is independent
of collision and gameplay state; this implementation does not animate light linking.

Static point instancers now expand into distinct mesh occurrences in a temporary
USD session. Prototype transforms, per-occurrence IDs and inactive/invisible masks
are retained. Prototypes must be descendants of the instancer; animated placements,
motion derivatives, animated prototypes and nested native instances require baking.
Expansion is limited to 4,096 occurrences, one million vertices, three million
indices and 100,000 prims. Runtime prototype residency is not retained.

Static `BasisCurves` now tessellate to capped round tubes. The profile accepts
nonperiodic linear or cubic Bezier curves with constant or per-curve uniform widths.
`userProperties:atlas_curve_sides` defaults to 8 (3..32); Bezier
`userProperties:atlas_curve_steps` defaults to 8 (1..64 per segment). Each mesh is
limited to 250,000 vertices/750,000 indices; aggregate bakes to one million vertices
and three million indices. Degenerate tangents, ribbons, periodic/other curve bases,
animated curves and nonconstant curve primvars are rejected. The tessellation is
an approximation with recorded settings, not an exact continuous curve renderer.
Sampled geometry/topology and runtime prototype retention still need implementation.
The geometry cooker now accepts USDZ directly. It validates entry names, uniqueness,
size/count limits and dependency membership before using a content-addressed
extraction cache. The current archive profile requires uncompressed, unencrypted
files and a root USD layer as the first entry. Imports record the original package
hash and reject missing dependencies or source changes before publication.

#### Atlas scene snapshots exported to USD

F12 in the world editor saves and exports the selected cell to a new directory under
`project/exports/usd-cell-*`. The export contains `scene.usda`, copied PNG textures
and `export.json` with input hashes and conversion policies. It preserves hierarchy,
persistent node IDs, double-precision transforms, triangle geometry, normals/UVs,
shared geometry references and supported opaque/masked PBR color/normal/ORM maps.
Built-in cubes and spheres are supported. Sources are checked for changes before
atomic publication; an existing destination is never overwritten.

```sh
python3 scripts/atlas-project.py usd-export --project /path/to/world \
  --source cell_0_0.scene --destination /path/to/new-usd-delivery
# Or export a standalone cooked/edited scene:
python3 scripts/export-usd.py --scene /path/to/edited.scene \
  --manifest /path/to/assets.atlas --destination /path/to/new-usd-delivery
```

This is a static scene snapshot, not a complete authoring round trip. Skin/morph
geometry, procedural terrain, foliage simulation, nonwhite vertex colors and
textured emission require baking and are rejected. Tangent frames are reconstructed
from normals/UVs. Texture wrap is authored; UsdUVTexture filtering is renderer-defined
and any nondefault source filtering is noted in the export report. Camera, light and
animation companions are not yet exported with a scene snapshot. Qualification
checks native USD reopen and Blender recooking after hiding the original assets.

#### Qualification and remaining roadmap

`scripts/qualify-usd.py` runs the native stage, material, geometry, camera and
existing importer tests, watcher/identity tests, animated camera/light loaders,
Vulkan camera/local-light rendering, morph interpolation/deformation and raster
references, composed visibility and render-cache parity, portable USDZ cooking, point/curve conversion, scene snapshot export and its
world-editor integration, the viewer and native authoring window.
The runner serializes access to shared fixtures, rejects stale engine builds and
records SHA-256 identities for the SDK sources, native USD tools and tested
executables. It refuses to publish if those inputs change during testing.
It publishes `build/usd-qualification/hardware.json` or `software.json` only after
all checks pass. It checks nonblank images, exact floating-origin image equality,
point-light distance/intensity scaling, spot direction/cones and 32-light accumulation.
Portable-package tests hide original layers before reopening the USDZ and loading
its payload. Reopen tests cover metadata, references, selected variants and edits.
These are independent USDA fixtures plus Blender export fixtures; no external
multi-DCC image-fidelity certification or large-world frame-budget result exists.

| Roadmap area | Implemented in this upgrade | Still required for completion |
| --- | --- | --- |
| Native stage/editor | Persistent API, selectable local override layers, undo/redo, native layer/prim/variant panels, automatic layer reload, explicit persistent IDs and loaded-prim collision repair, time-sampled edits and revisioned 3D viewport with TRS/skin/morph/camera/light playback | Vector/transform curve editing and tangent handles; full profile qualification of M02 owned source targets and payload/proxy identity reconciliation |
| Cameras/lights | Animated rigid cameras and physical exposure, distant/dome tracks, static unshadowed point/spot profile, units/temperature | DOF/motion blur, area/shadowed local lights, full UsdLux, HDR domes and texture/display OCIO |
| Materials | Preview Surface, strict constant Standard Surface/OpenPBR approximations and tagged constant-color OCIO conversion | General MaterialX graphs, texture networks, advanced lobes and visual reference tolerances |
| Geometry/animation | Skin/TRS, morph weight animation with CPU deformation, composed mesh visibility, subdivision/round-curve bakes and expanded native/point instances | Runtime prototype retention, animated point placement, other curve profiles, GPU morph computation, in-between shapes and geometry caches |
| Streaming | Selective payload authoring, bounded background requests, process/prim limits | USD-driven runtime residency/LOD, background renderer publication and measured world CPU/GPU/frame budgets |
| Authoring/export | Overrides, metadata-preserving reopen, portable USDZ and static Atlas scene/cell snapshot export | Animation, skin/morph, terrain/foliage and vertex-color material export; complete authoring round trips |
| Interoperability | Versioned profile, regression runner, GB10/software image checks | Versioned exports from multiple independent DCCs, reference-render comparisons and sustained performance qualification |

Hydra integration remains optional renderer interoperability work. Nothing in this
profile establishes full USD conformance or comic-to-game visual identity.

```sh
pixi run world-demo
pixi run character-demo
pixi run library-test
pixi run atlas-benchmark
```

The partition editor stores its default world in `build/atlas-world-project`.
Choose a durable project directory outside build outputs when authoring a world:

```sh
pixi run bash scripts/run-vulkan.sh build/atlas-world --project /path/to/world
python3 scripts/cook-assets.py model.glb --output /path/to/world/cooked --id robot
pixi run bash scripts/run-vulkan.sh build/atlas-world \
  --project /path/to/world --assets /path/to/world/cooked/robot-assets.atlas
```

Create the project's parent directories first. `atlas.project` stores versioned
name/cell-size/seed settings and relative manifests; reopening loads those assets.
Default primitive IDs are `atlas/cube` and `atlas/sphere`. Project settings and
world cells use durable writes; object cells and terrain share the redo journal.

The editor supports searchable assets (F3), an asynchronous import dialog (F7),
asset reload (F8), hierarchy selection/scrolling, and property editing (F4; Tab
changes position/scale/quaternion/material fields). Imported content publishes
immutable dependency generations. Supply `--sdk /path/to/atlas-sdk` when launching
from another working directory. F2 swaps the panel docks and persists placement.

Drag assets into the viewport. Click or Ctrl-click to select up to 128 objects.
1/2/3 choose move/rotate/scale gizmos; L selects local/world axes; G enables a
one-unit positional grid. Arrow/Page keys move; R rotates; +/- scales. Keyboard
multi-object transforms form one undo command and move selected roots with their
hierarchies across cells. U saves the selected subtree as `prefab.scene`; V places
an instance with new persistent identities. B duplicates and X deletes selected root subtrees as one command.
Z/Y undo/redo up to 32 commands, storing changed nodes and terrain samples.

Gizmo drags preview the complete selection without changing authored transforms;
saves during a preview retain the original world. Parent/child selections transform
only the selected ancestor. Release commits one command, including cross-cell
hierarchy moves. A changed/unloaded/reparented source cancels its gesture; keyboard
commands cancel the active drag. World-grid snapping accounts for transformed
parents. Duplicate preserves a selected child's original parent and gives every
clone a fresh identity. The preview limit is 128 objects and hierarchy depth 256.

H selects sculpt and P selects paint; click applies a stroke, Shift lowers, and
wheel changes radius. `TerrainLayer` uses an owned sparse global lattice and
bilinear height/color sampling across chunks and LODs. CPU terrain contact samples
the same height. Edits retain old chunks until matching worker replacements are
uploaded. A layer has at most 65,536 samples; strokes at most 16,384. The reserved
terrain cell is validated and committed with object cells. This is vertex-color
terrain painting, not layered terrain textures. Large edit histories and layer
snapshots consume CPU memory in addition to GPU residency budgets.

F5 queues saves; F9 flushes and reloads cells. Exiting flushes dirty revisions.
C switches between fly and capsule walk; placed cubes also receive box collision.
T teleports one billion units. F6 exports an isolated simulation copy and opens
its player; stop closes the child and removes only the marked, inactive play copy.
Authoring pauses during project operations. F10 exports current content with the
local compiled player, a launcher, hashes, and SDK runtime libraries. The exported
player needs the matching Linux architecture, system SDL2 and Vulkan driver.
Runtime exports are platform-specific; copying a local player does not establish
support on other machines. Isolated play passed on lavapipe and GB10: the child
presented a frame, stopped, and its owned simulation copy was removed while the
authored landmark remained. The extracted SDK built independently and passed the
full synchronization-validation suite plus Xvfb presentation/resize on both
drivers. A visible desktop authoring session remains unqualified.

Project operations are also available through `scripts/atlas-project.py`:

```sh
pixi run python3 scripts/atlas-project.py create --project /path/to/world
pixi run python3 scripts/atlas-project.py import --project /path/to/world \
  --source model.glb --id robot
pixi run python3 scripts/atlas-project.py check --project /path/to/world
pixi run python3 scripts/atlas-project.py export --project /path/to/world \
  --destination /path/to/export --sdk .
```

Exports reject missing/escaping dependencies, committed unrecovered journals,
existing destinations and open writers. The editor explicitly exports its flushed,
paused snapshot. File counts and total export bytes are bounded. Prefab file
saving and project settings are durable operations outside world undo history.
The editor remains an example application; OS file dropping and arbitrary floating
panel layouts are not implemented. World-space rotation under nonuniformly scaled
parents is limited by the TRS representation; shear is not an authored transform.

## Streaming and ownership

`WorldStreamer(config, asynchronous=True, upload_ms=2, scheduler=shared)`
uses a shared `StreamScheduler` when supplied. The editor shares four CPU workers
between terrain, cell I/O and collider preparation; private queues retain their one-worker behavior.
Near rings and camera travel direction determine priority, with aging to avoid
starvation. Small camera moves retain useful queued/prepared results and cancel
obsolete requests. Workers own CPU data and never call Vulkan. A count limit and
soft upload-time limit bound main-thread preparation; an individual upload can
exceed that time limit.

`mesh_byte_budget` bounds the worst-case live terrain vertex/index payload,
including skirts, across the configured neighborhood. A coarser LOD bias is
chosen if needed; configurations that cannot fit even at minimum quality fail.
This payload budget excludes allocator pages, staging and other GPU resources.

`WorldPartition(path, asynchronous=True, scheduler=shared)` serializes its own
reads and grouped save transactions while other clients run concurrently. Dirty
revisions are snapshotted together. Completion cleans only matching revisions.
Dirty cells survive slow/failed I/O; new residency is throttled above the normal
neighborhood plus eight. Explicit `save()` joins this client and flushes newest
revisions. `ensure()` loads an offscreen cell synchronously.

`StreamScheduler` bounds total jobs and estimated CPU reservations (64 MiB by
default), reserves up to 4 MiB and a job slot for saves, and permits independent
client cancellation/restart. The reserve does not guarantee admission of an
arbitrarily large transaction. Closing one client joins its active work without
stopping other clients. Queue depth/reservations are client-specific; lifetime
counters and peak reservations describe the shared scheduler. RSS, native
allocator overhead and GPU allocations are measured separately.

World directories have a single-writer advisory lock. Multi-cell commits stage
bounded, checksummed payloads, fsync them, then publish and sync a redo manifest.
Recovery validates every payload before replay and finishes a committed move
before loading cells. Precommit interruption retains the previous revision.
Active objects have persistent IDs; transfers and undo preserve them. Placement
creates a new ID. New saves use `MOJO_SCENE_3`; versions 1 and 2 migrate on load.
An explicit `Scene3D.compact()` remaps indices while preserving persistent IDs;
callers must discard or remap any index-based undo history before using it.

## Rendering and resource lifetime

`DirectionalShadows3D` fits two or four overlapping camera-frustum volumes and
aligns their light-space centers to world texels in double precision. A shared
4096-square depth atlas contains 2048-square cascade tiles; sampling clamps PCF
taps to each tile and blends over the final ten percent of a split interval.
The editor defaults to four cascades over 256 metres. Launch with
`--shadow-cascades 2` for fewer shadow submissions or `--shadow-cascades 0` for
the existing single-map path. Cascades reuse atlas memory but multiply shadow
draw recording/submission work; they are a quality/cost setting, not free detail.

Prepare with the exact projection near/far distances and camera-forward direction.
Matrices and `camera_offset` use the draw origin; `world_origin` supplies texel
alignment only. `Graphics3D.shadow_cascades(matrices,splits,forward,camera_offset)`
begins the frame. Submit casters using the combined `cull_matrix`, then call
`begin()` and submit color geometry. Caster padding bounds included occluders
outside the camera view. The private GPU block has a separate main/cascade slice
in each frame bank; the public `Frame` layout and existing function signatures
remain unchanged. `shadow_begin()` resets cascade/debug state to the legacy path.
`shadow_debug()` displays atlas depth on submitted color geometry for inspection.

Cascade fixtures cover overlapping fit, vertical sun direction, all four populated
tiles, actual shadows, alpha-tested and skinned casters, the water-depth pass,
one/two-bank image parity and legacy reset/resize. CPU/GPU skin mean error is zero
in this fixture on lavapipe and GB10. Billion-unit translated captures are identical
with stabilization disabled; world-grid snapping may change phase under a global
translation, and that comparison does not establish shimmer or transition quality.
The independently built SDK passed the full software suite and GB10 window/cascade
checks; frozen evidence is in `build/atlas-qualification/directional-cascades-20261001T132342Z`.
Three 1080p/1,024-object runs measured GPU medians of .158–.163 ms (single map),
.174–.177 ms (two cascades) and .211–.212 ms (four). The baseline runs overlapped
compilation; these observations are not a frame-time regression gate. Broader
shimmer/transition scenes remain open.

`Graphics3D.hdr(True)` opts into FP16 (`R16G16B16A16_SFLOAT`) scene radiance,
MSAA resolve and opaque water inputs. Exposure, the ACES-fit filmic curve and
piecewise sRGB encoding execute once in a fullscreen pass; overlays follow in
RGBA8 display space. Clear/fog colors use linear `lighting(...,haze,exposure)`
values in this mode. HDR view-dependent lighting, water reflections and fog use
`camera_origin(eye-draw_origin)` when the eye differs from the draw origin.
Call it after `shadow_begin`; cascades already supply their camera offset.
The swapchain/snapshot remains SDR RGBA8; this does not
request an HDR monitor output mode. Albedo textures decode sRGB in Vulkan;
normal/ORM maps and material/vertex colors remain linear. Scene radiance is
bounded to 60000 before FP16 storage to avoid infinities. Mode changes synchronously
retire/recreate targets and descriptors, so select a mode during loading.
The legacy mode remains the library default and allocates no HDR target images.
The editor and reference game enable HDR and low-frequency environment lighting;
`--legacy-lighting` selects the comparison path. Shadow quality is independent.

`Environment3D.constant`, `.hemisphere` and `.latlong` project linear distant
radiance into nine Y-up spherical-harmonic coefficients. Panorama projection
accepts at most 262144 RGB samples, dimensions at most 2048, radiance 0..60000,
and exact row solid angles. Call `device.environment(environment)` once during
loading; the setting persists until explicitly disabled. It replaces hemisphere
ambient with diffuse irradiance and broad roughness-filtered reflections. Nine
terms cannot preserve sharp mirror reflections: prefiltered high-frequency
cubemaps/BRDF LUTs and HDR-file import remain future quality additions. The diffuse
convolution follows [Ramamoorthi and Hanrahan](https://lightfield.stanford.edu/papers/envmap/).
The FP16 format is defined by the [Vulkan format specification](https://docs.vulkan.org/spec/latest/chapters/formats.html).

HDR fixtures check known radiance/exposure values, exact sRGB texture decoding,
linear water scaling, environment material response, unchanged UI colors,
MSAA 1/4, both frame banks, resize and restoration of the legacy allocation total.
The final camera-origin correction passes bit-identical origin captures on GB10.
Root and independently built SDK full suites pass with synchronization validation;
SDK manifests/source fingerprints match. Custom HDR Xvfb mode switches pass on
both drivers, isolated GB10 editor play cleans its simulation, and the reference
game built using the SDK compiler/API/archive completes its route/save/reopen.
Evidence is frozen in `build/atlas-qualification/hdr-environment-20261001T140803Z`.
Matched 1080p/four-cascade/1024-object runs measured GPU medians .217–.220 ms
(legacy lighting) and .255–.256 ms (HDR/SH), with about 25.31 MiB extra native
Vulkan allocations. Host medians vary; these are fixture costs, not a whole-game
frame-time guarantee. Final sustained/visible-desktop qualification remains open.

`Graphics3D.draw_instances(mesh, matrices, material, origin, shadow)` issues one
indexed instanced draw. Color, alpha-tested shadow and camera-depth passes share
the instance matrices and inverse-transpose normals. Ordinary and morph draws
bind an identity instance; existing function signatures stay supported.
`Assets3D.draw` evaluates hierarchy matrices once per submission, culls objects
and batches matching mesh/material combinations. Its shadows now carry textures.
Batching can be disabled with `batched=False`. The instance stream has a 65,536
matrix capacity per frame, shared by all passes including its identity entry.

`Assets3D.draw_cached` uses a scene-owned `SceneDrawCache` to prepare transforms,
world bounds, resolved materials and numeric batch identities once per revision.
Its bounded spatial tree rejects branches and preserves source submission order.
The same cache serves shadow and color passes. Each `WorldCell` owns a cache;
the editor uses it for committed scenes and the uncached path for drag previews.
Retained cells preserve ownership and ordering instead of copying scenes on
every update. Cache data is CPU memory outside terrain/GPU residency budgets.

The cache belongs to one scene and asset registry. Callers must increment the
scene revision or call `invalidate()` after any node mutation; direct public node
writes cannot be detected automatically. Asset reloads invalidate through the
asset revision. A failed preparation preserves the old cache but propagates the
error. Use `hierarchical=False` for cached linear culling comparisons; ordinary
`draw()` remains available without a revision contract. Animated skeleton draws
continue to use their conservative GPU-skin bounds separately.

### Static HLOD and foliage

Cook a static glTF with explicit hierarchy aggregation and optional position error:

```sh
python3 scripts/cook-assets.py static.gltf --output cooked --id town \
  --hlod-distance 80 --hlod-transition 12 --hlod-error 0.25
```

The cooker groups compatible material sources into 64-metre spatial clusters,
bakes them relative to each cluster center and emits `town-world.atlashlodb` plus
proxy meshes in an immutable generation. Normal, UV, tangent and color seams are
preserved. Voxel representatives bound vertex displacement by the declared error;
this is a geometric bound, not a screen-space silhouette guarantee. Zero error
merges without simplifying. Animated/morph scenes and wind-driven foliage are
excluded from this static bake. At most 4094 clusters, 100000 source nodes,
250000 vertices and 750000 indices per mesh are accepted; split oversized clusters.

Load the **binary** asset manifest and matching source scene before
`HLOD3D(metadata_path, assets)`. Call its `draw(assets, device, scene, revision,
camera_world, draw_origin, view, shadow)` in both passes with the same camera.
One HLOD object/cache belongs to one scene. Change revision after edits. Cooked
source/proxy fingerprints must match the registry. Changed source identities,
transforms, materials or asset revisions use original geometry. Set `enabled=False`
to compare cached source rendering; `transitions=False` selects immediate switches.
HLOD is an opt-in library/cooker path; the editor does not automatically rebuild
static proxies from arbitrary partition edits or prefab placements.

`draw_lod_instances` uses complementary deterministic screen-pixel coverage in
color, shadows and water depth. Both levels share a threshold; near keeps
`1-threshold`, far keeps `threshold`. It supports static colored/tangent meshes,
alpha masks and foliage wind. It consumes no temporal history; the pattern can
remain visible in a transition. Both meshes are submitted during the interval.
The same-geometry fixture matches the unfaded frame exactly at all thresholds on
lavapipe and GB10, with MSAA 1/4 and both frame banks.

A material's glTF `extras.atlas_foliage` object accepts `transmission` (0..1),
`wind` (boolean) and `padding` (0..16 local units). Defaults are .6, true and .25.
Wind requires nonzero transmission and padding at least .201, covering the native
maximum amplitude .25 along its wind direction. Bounds expand before hierarchy
scale/rotation. Cooked policies are stored in binary manifest row kind 5 (or a
28-field text material row); older material rows continue to load. Identical cooked
geometry batches by content fingerprint even when stable asset keys differ.
GPU mesh registrations remain separately owned. Repeated policy reloads retire
both textures and their bound metadata. Static collision remains the authored
unanimated geometry; it does not follow leaf wind.

`WorldStreamer(..., transition_seconds=.2)` retains the previous LOD while fading
a matching revision. Pass elapsed seconds to `update(device,camera,dt)`; the
library default is immediate switching and its default timestep is 1/60 second.
The editor enables .2-second fades. Residency planning plus retained overlap must
fit `mesh_byte_budget`; insufficient headroom selects immediate replacement.
`transition_bytes`, `transition_count` and `immediate_count` expose this choice.
A paint revision also includes retained overlap in its residency check and leaves
the current layer/revision unchanged on rejection; retry after the fade retires.
A second replacement waits until the active fade finishes. Eviction/close releases
both generations. Edited revisions retain the prior ready chunk until upload and
then replace immediately. Sync and shared-worker paths have progression, budget
fallback and stale-handle tests on both drivers.

The three-surface fixture reduces far submissions from three to one. Its .5-metre
simplification reduces 2400 to 1102 triangles, with mean byte error .027 in its
fixed 400x240 capture; exact aggregation and billion-unit rebasing are identical.
Three 1080p GB10 runs measured reduced-proxy GPU medians .081–.083 ms versus
.085–.086 ms for originals, and .091–.092 ms during the fade. Host medians vary
substantially. This small fixture establishes a measured tradeoff, not a dense-world
frame-time guarantee. Final artifact evidence and sustained gates are recorded in
[Validation](VALIDATION.md).

### Temporal evaluation

`scripts/evaluate-temporal.py` is a bounded offline linear-radiance reference study.
Exact camera/object motion vectors, jitter, previous-surface depth rejection and
neighborhood color clamps exercise moving occluders and revealed surfaces. Across
32 fixed 64x48 frames, background MSE versus a 4x4-sample reference drops from
.112209 for point samples to .014055 after warmup. The study rejects 1874 depth-
mismatched history samples and preserves origin-relative results at one billion.
These are software reference measurements. Vulkan motion attachments, GPU history,
skinning/wind motion and runtime TAA are not implemented or enabled. Perspective,
transparency, ghosting/shimmer across broader content and GPU cost remain gates
before offering a temporal rendering mode.

Mesh vertices and indices use 8 MiB pool pages with 256-byte-aligned slices.
Ranges retired by released handles are reclaimed after the submission fence.
Pages remain allocated for reuse until device close. Pool backing buffers are
limited to 64 pages and 512 MiB requested capacity; Vulkan allocation padding,
textures, frame targets and staging buffers are outside that capacity limit.
`MOJO_VK_MESH_POOL=0` retains individual mesh allocations for comparison.

Coherent mapped pools remain the default for GB10. Setting
`MOJO_VK_DEVICE_LOCAL_MESH=1` batches owned mesh copies through two 8 MiB staging
slots. Copies share submissions; fences protect slot reuse. Transfer dependencies
cover overlapping updates and later vertex/index reads. Mesh slices retire against
monotonic submission serials, including pending copies. `flush_uploads()` submits
queued copies explicitly; render also flushes them. `upload_stat()` reports waits,
batches, writes, bytes, staging allocations and completed serials.

Two frames in flight are the default; `MOJO_VK_FRAMES_IN_FLIGHT=1` retains a
comparison mode. Each bank owns command/fence/acquire/query resources and separate
aligned uniform, instance and overlay data. Render-target access is ordered on the
shared queue. Window rendering and blitting share one submission. Snapshot and
resize remain synchronous; stream growth waits for existing GPU use before
replacing buffers. `update_mesh()` still waits for prior use of that mesh.

`frame_stat()` identifies submitted renders and the render associated with GPU
timing. With two banks, GPU timing is harvested when a completed bank is reused,
so it refers to an earlier render. No timing is reported before a completed query.
Fixed 1080p GB10 streaming comparisons (three runs per mode, 120 warmup and 1,000
total frames) measured one-bank host medians 0.68–0.82 ms and two-bank medians
0.37–0.41 ms. These are headless streaming fixtures, not qualification of the
roadmap's playable-world/windowed target. Frozen reports are under
`build/atlas-qualification/20261001T080657Z` through `20261001T080711Z`.

## Assets and animation

The offline cooker accepts OBJ, glTF 2.0 JSON and GLB. Typed little-endian
`.atlasmeshb`, `.sceneb`, `.atlasb`, `.atlasskeletonb`, `.atlasskinb`, `.atlasclipb`
and `.atlascollisionb` files share a version-2 envelope with payload length,
kind, checksum and a checksummed relative dependency table. Reads are bounded
at 64 MiB per file and 256 MiB per dependency set. Old text counterparts remain
available for migration; scene versions 1/2/3 still load.

Cooking freezes a content-addressed dependency generation before publishing
root manifests. Readers retain access to the previous generation. Cache repair
checks both aliases and generation files. Generations are retained on disk;
there is currently no automatic garbage collector. Stable node/material keys
prefer explicit `extras.atlas_id`, then unique names, then source slots.
Primitives prefer `extras.atlas_id`, then slots. Author explicit IDs when
anonymous source slots or names may change.

Sparse accessors, authored tangent channels, default morph shapes and
CUBICSPLINE TRS tracks are supported. Morph deltas and tangents are preserved in
binary meshes; default morph deformation is applied before rendering/skinning.
Authored tangents and normalized RGBA vertex colors reach the GPU and CPU skin
reference. Sampler repeat/clamp/mirror, nearest/linear/mipmap filters and
OPAQUE/MASK alpha cutoff policies are retained. ORM packing requires matching
samplers. Animated morph weights remain unsupported, as do required extensions,
blended materials, non-unit alpha/normal factors and texture transforms. Unknown
vertex attribute channels are rejected. glTF documents bound array counts, index
references, affine transforms, image sizes and per-file/dependency bytes.
The document also has a depth-64 and one-million-value budget, including ignored
extras/extensions. Public cooking turns malformed shape, numeric overflow and
parser nesting errors into useful failures. Fifty-three malformed fixtures check
these paths and preserve previously published manifests; this is bounded fixture
coverage, not a broad fuzz campaign.
Pillow is an offline image-cooking dependency; runtime loading uses Mojo.

`Assets3D.replace_mesh` prepares a valid replacement before publication, retains
stable asset indices and releases the old mesh after queued consumers submit.
Native completion serials protect GPU slices. `reload_manifest` privately
prepares and validates a dependency set before publishing mesh/material/collision
replacements. Texture IDs carry generations; up to 256 slots may be live at once.
Retirement respects queued draws, unfinished GPU serials and attached normal/ORM
sources. Failed unpublished candidates free created resources. Reloads prune
obsolete ownership/dependency entries and release textures once consumers permit.

`SkinnedMesh.gpu_data` provides joint position/normal palettes and four influences.
`Graphics3D.draw_skin` uses the same deformation in lit, alpha-tested shadow and
opaque depth passes. CPU deformation remains the reference. Copied skin data is
shares a 16 MiB per-frame stream with vertex colors/tangents, banked across two
frames; GPU storage is allocated on first use. Optional mesh color/tangent CPU
copies have a 128 MiB total budget. Legacy vertex-frame morph blending is rejected
when optional attribute streams are present; default glTF morph shapes still work.
`gpu_bounds` conservatively encloses palette-deformed bind bounds. Triplanar/foliage materials are rejected on this skin path because
they share pose storage. The character example now uses GPU skinning.

`Animator3D` supports configurable states, interruption-safe pose fades, loop
markers and optional translation root motion. Update it on a fixed step and feed
its root displacement through `CharacterController3D.step_root_motion`, which applies collision and gravity. `ActionMap` gives keyboard
and controller actions stable names, with focus suppression and a radial deadzone. `ThirdPersonCamera` sphere-sweeps obstruction and supplies
views relative to a floating origin. `Navigation3D` builds bounded, single-height
ground tiles from loaded collision and searches capsule-clear edges; callers
remove/rebuild tiles when collision changes. It is not a layered navigation mesh.

## Capsule movement

`CharacterController3D` supports authored boxes and BVH triangle geometry, swept
capsules, snapping, steps, jumps, overlap recovery and moving supports. The cooker
emits validated static triangle BVHs. `CollisionStreamer3D` prepares a cell before
publication, preserves old collision on failure, frees evicted geometry and
invalidates stale support handles. Call `ready()` before entering a streamed cell.
Its payload budget defaults to 64 MiB; the default publication count is one cell
per update. Optional asynchronous preparation shares `StreamScheduler`; the editor
and reference game enable it. A worker cell accepts at most 256 collider instances,
4 MiB per encoded collider/dependency and 16 MiB prepared geometry, with a 48 MiB
reservation. Main-thread publication retains old collision until the entire
replacement validates. Synchronous callers retain the larger general asset limits.
Count limits are not a hard main-thread deadline. Temporary allocations are
estimated separately from resident geometry. Procedural terrain retains bounded spatial sampling.

The solver has bounded iteration counts and is intended for fixed timesteps.
Rotating platforms, difficult stacked bodies and general rigid-body dynamics
remain outside the tested controller contract.

## Validation and measurements

`tests/atlas_systems.mojo` checks cancellation, worker restart/errors, hierarchy
transfer, delta undo/save, thin-wall sweeps, stepping/platform motion, clip
sampling/blending, CPU skinning and inverse transforms. `tests/cook_assets.py`
checks glTF/GLB inputs, dependency/output cache invalidation and bad accessors.
`tests/atlas_render.mojo` compares instanced and individual snapshots byte-for-byte,
checks pool reuse/stale handles/dynamic meshes, resolves stable IDs after unrelated
asset registration and loads asynchronous terrain at billion-unit coordinates.
The library suite additionally runs both new examples headlessly.

`bash scripts/benchmark-atlas.sh baseline|current|instanced` records 90 measured
frames after warmup for a fixed 1,024-cube scene, with executable/archive hashes.
Baseline is a historical recording; do not overwrite it to compare a later build.
Host and GPU stages overlap and must not be added. These headless measurements
are not windowed scanout latency or general game performance.

`bash scripts/benchmark-atlas.sh streaming` records 600 measured frames while
travelling through terrain and teleporting one billion units halfway through.
The report includes host/GPU percentiles, residency, uploads/evictions, peak
worker reservations and Vulkan allocation bytes. Timing is observational; this
short run is not a long-duration soak or a guaranteed frame-time threshold.

On NVIDIA GB10, the 1,024-cube instanced submission used one color draw rather
than 1,024, with byte-identical individual/instanced regression snapshots. The
600-frame streaming run completed 607 uploads and 247 evictions, ending with 72
resident chunks. Peak worker reservations were 2,157,984 bytes; requested Vulkan
allocations were 94,979,008 bytes. Observed host median/p95 were 0.596/0.964 ms
and GPU median/p95 were 0.291/0.309 ms. Full reports under `build/atlas-benchmark`
record binary/archive/source hashes; these short headless observations include
scheduling noise and do not establish a portable speedup.

## Import allocation limits

The cooker rejects JSON larger than 16 MiB, nesting deeper than 64 and excessive
lexical tokens before Python parsing. Accessor/mesh instance expansion is preflighted
before buffer reads against a cumulative 512 MiB **estimated work** budget. This is
not an RSS guarantee or a process memory limit. Source/cooked files remain bounded
to 64 MiB; retained outputs are checked on every insertion/replacement against
256 MiB. Mesh cooking accepts at most 250000 vertices/750000 indices; OBJ lines are
limited to 1 MiB and 65536 tokens. ORM packing uses a byte buffer. A repeated large
mesh is rejected cleanly under a 256 MiB process address-space test limit, and 256
seeded malformed imports preserve the previously published generation. These
fixtures do not establish exhaustive parser fuzz coverage.

### Completion gates for the remaining USD work

The [current roadmap](ROADMAP.md) defines execution order, starting with durable
layered workspaces (M01). The rows below are compatibility coverage gates, not
a separate implementation sequence. Local override targets are implemented;
separate local layers persist across restart (M01). Source/reference working targets and payload/proxy identity reconciliation have M02 targeted checks; their complete profile qualification remains pending.

Each row below remains open until its deliverables and evidence both exist. Passing
the finite compatibility profile does not close these gates.

| Order | Deliverable | Required acceptance evidence |
| --- | --- | --- |
| 1 | Vector/transform curve editing and tangent handles, existing-layer edit targets and identity reconciliation for unloaded payloads/proxies | Referenced asset edits land only in the selected writable layer; undo/reopen retain authored values; two instances do not alias identities |
| 2 | Camera DOF/motion blur, HDR domes, area lights and shadowed local lights | Versioned source scenes and reference images for exposure, DOF, light shape, shadow softness and color transforms, with declared image-error tolerances |
| 3 | MaterialX graph/texture execution and advanced lobes | Supported-node inventory; connected texture/normal/coat/transmission fixtures; unsupported graphs fail explicitly; renderer comparisons across the declared profile |
| 4 | Runtime prototype retention, animated point placement, broader curve profiles, GPU morphs/in-between shapes and geometry caches | Imported fixtures sampled at start/mid/end; interpolation and topology limits tested; measured memory does not scale as expanded geometry for retained instances |
| 5 | Runtime payload residency/LOD and background publication | Traverse a representative world under declared CPU/GPU memory and frame-time budgets; load/cancel/evict/fail safely; no stale handles or visible missing dependencies |
| 6 | General Atlas edits exported to USD | Modify transforms, materials, geometry, cameras and animation in Atlas; export and reopen in another DCC; verify units, IDs, references and values |
| 7 | Independent interoperability and sustained performance qualification | Named DCC versions and externally produced exports; reference renders; target resolutions/frame budgets; long traversal logs and reproducible hardware/software evidence |

The production team still needs to choose the additional DCC targets, supply their
reference exports/renders, and approve visual tolerances and world performance
budgets. These are release requirements, not values inferred from a successful
Blender import. The comic-faithful game also needs approved character turnarounds,
sculpt/rig/animation assets and panel-to-shot comparisons beyond USD interoperability.
