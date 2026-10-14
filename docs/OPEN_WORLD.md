# 3D and open-world API

The asynchronous streaming, partition editor, stable assets, instancing and
skeletal-animation APIs are detailed in [Atlas upgrades](ATLAS_UPGRADES.md).

## Coordinates and precision

The new renderer uses a right-handed coordinate system: +Y is up, cameras face
-Z, matrices are column-major, and vectors multiply on the right. Units are
meters by convention. The legacy `Camera`/`Raster` API keeps its original +Z
software-renderer convention; do not mix its projection with `Mat4`.

`Vec3`, `Quaternion`, `Transform3D`, `Mat4`, scene hierarchies and camera
positions use Float64. Mesh vertices are local Float32. `gpu_matrix(matrix,
origin)` subtracts the Float64 camera origin from translation **before**
converting to Float32. View matrices use a camera at zero with the real camera's
orientation. Lights and shadow views use the same relative coordinate space.

`Quaternion.axis_angle`, multiplication, normalization, rotation, and shortest-
path normalized interpolation support object orientation. `Mat4.perspective`,
`orthographic`, and `look_at` validate degenerate projection/camera parameters.
`Transform3D.matrix()` composes translation, rotation and scale. Renderable
transforms must have nonzero scale for valid normal matrices.

## Graphics ownership and passes

`Graphics3D(title,width,height,hidden)` owns a Vulkan instance/device, an optional SDL window/surface, meshes,
textures, shadow target and overlay batch. Only use it on the creating thread.
One active window is supported per process; hidden mode creates no display surface. Its destructor and `close()`
release resources; close is idempotent. Methods other than close require a live
device. The graphics C bridge is linked statically;
GLSL is compiled to embedded SPIR-V at build time. Vulkan failures surface as Mojo exceptions.

A frame is:

1. `device.poll()` updates input and drawable dimensions.
2. Compute a camera-relative view-projection and directional light matrix.
3. `shadow_begin(light_matrix)` then `shadow(mesh,model,origin)` for casters.
4. `begin(view_projection,sun_direction,fog_density)` then `draw(...)` for color.
5. `rect(...)` and `text(...)` append overlay primitives.
6. Optionally `snapshot(path)`; then `present()` renders pending draws and presents.

Draws are queued on the CPU, validated, and recorded into Vulkan command buffers
when a frame is rendered. `shadow_begin` starts a new frame and clears its queues;
call it even when there are no shadow casters. Snapshot and presentation share the
same rendered color image. A Vulkan swapchain is only used for visible windows.
The backend uses two frames in flight with separate writable data banks and
pooled coherent mesh buffers. Device-local uploads use a bounded staging ring.
`MOJO_VK_FRAMES_IN_FLIGHT=1` selects the serial comparison mode. See [Vulkan details](VULKAN.md).

`upload(mesh)` returns a generational GPU handle. `release(handle)` frees it;
stale handles raise an error. There are 4096 mesh slots. `update_mesh` changes
vertices while preserving matching index topology; topology changes require a
new upload and release. Textures are window-owned, with 256 slots, and are released at close.
`texture(path)` accepts BMP, uploads sRGB pixels, and generates mipmaps.

`Material(color,roughness,metallic,emission,texture)` uses linear RGB colors,
roughness clamped to [0.045,1], metallic to [0,1], and nonnegative emission.
The shader includes direct GGX lighting and a hemisphere ambient approximation.
It has one directional sun and a 4096² shadow atlas. Optional linear FP16 HDR
uses one final exposure/filmic/sRGB display pass and display-space UI.
`Environment3D` provides diffuse and broad-reflection distant lighting from nine
SH coefficients; sharp mirror maps, temporal antialiasing and deferred lighting
remain open. Directional cascades are now
available through `DirectionalShadows3D` and `Graphics3D.shadow_cascades`; the
editor uses four by default and retains two/single-map quality settings. Their
API and validation limits are described in [Atlas upgrades](ATLAS_UPGRADES.md).

`Assets3D` caches meshes by key and stores bounds. `add(device,key,mesh)` and
`load(device,path)` return stable asset-table indices. Saved `SceneNode.mesh`
values refer to those indices for legacy callers. `SceneNode.asset_key` and
`material_key` instead resolve stable manifest IDs independent of registration
order. `assets.draw(device,scene,origin,vp,shadow)` validates references, computes
world transforms once, culls transformed bounds and batches matching geometry. `pick` performs
nearest world-AABB ray selection; it is not triangle-accurate. Close the cache
before its device. Duplicate keys reuse the first uploaded asset.

## Scenes and editing

`Scene3D` contains `SceneNode(name,transform,mesh,material,parent)` records.
`add` returns a stable index. `reparent` rejects cycles; it preserves the local
transform. `world_matrix` composes ancestors. `remove` deactivates a subtree;
indices are never recycled. Public node data is convenient for editing, but
callers must preserve valid parent links and nonsingular transforms.

`encode/decode` use `MOJO_SCENE_3`, which includes persistent object IDs alongside
asset/material keys. Versions 1 and 2 still load and migrate identities. Parsing
rejects malformed records, non-finite numbers, singular transforms and invalid
active hierarchies. `save` syncs a sibling temporary file before renaming it.
`WorldStore` adds directory synchronization, a writer lock and redo transactions
for durable multi-cell commits. `Scene3D.load` also accepts cooked `.sceneb` files.
`compact()` explicitly removes tombstones and returns the old-to-new mapping;
callers must reset/remap index-based history when using it.

`SceneEditor` applies transform and selection commands to an application-owned
scene. `checkpoint` captures a state before editing; undo history is bounded to
32 scenes. The editor example adds mouse picking, outliner selection, save/load,
physics spawning, and render statistics. It is a lightweight scene editor, not
a full dockable authoring environment.

## Terrain streaming

```mojo
var config = TerrainConfig(seed=42, chunk_size=64, radius=4,
                           resolution=32, chunks_per_update=2)
var world = WorldStreamer(config)
world.update(device, camera.position)
# In each render pass, pass the appropriate view-projection for culling:
world.draw(device, camera.position, False, view_projection, True)
# Before destroying the device:
world.clear(device)
```

Terrain uses deterministic multi-scale value noise with analytic global
coordinates. Heights span at most [-44,44]; normals use finite differences.
The central 3×3 chunks use full resolution, the next ring half resolution,
and distant chunks quarter resolution. All levels include vertical skirts.
This hides cracks but is not geomorphing: LOD changes can pop.

A radius R retains at most `(2R+1)²` chunks. Each update first evicts chunks
outside the radius, then processes missing/replacement meshes in near-first
rings up to the configured budget. Replacements are uploaded successfully
before old meshes are released. Generation and upload happen synchronously by
default. `asynchronous=True` prepares meshes on a bounded worker queue; an
additional soft `upload_ms` budget bounds submission work. See the upgrade guide
for cancellation, memory reservations and thread ownership. There is no disk heightmap cache.
A teleport can temporarily show missing far chunks while residency catches up.

## Disk-backed world cells

`WorldPartition(directory,cell_size=256,radius=1,budget=2)` manages authored
scene cells named `cell_X_Z.scene`. Create the directory first. `update(camera)`
loads a near-first, bounded number of cells, treats absent files as empty cells,
and saves dirty cells before eviction. Parse/read/write failures propagate;
failed writes keep resident content. `find(x,z)` returns the resident list index;
indices can change after an update. Reacquire them when accessing cells.

```mojo
partition.update(camera.position)
var cell = partition.find(0, 0)
# Edit partition.cells[cell].scene, then:
partition.mark_dirty(0, 0)
partition.save()  # explicit flush before shutdown
```

All root transforms in a cell are world-space. Applications decide which cell
owns an object, handle transfers across boundaries, and establish the stable
asset table for every file. Hierarchies cannot span files. Dirty tracking is
explicit; the destructor cannot report failed saves. `asynchronous=True` prepares
reads and snapshot writes off-thread. `WorldEditor` implements hierarchy transfers
and delta undo across cells; `atlas-world` demonstrates partition authoring.

## Simulation and lifecycle

`Physics3D` stores stable-index `Body3D` spheres. Mass zero is static. Dynamic
bodies integrate gravity with substeps at most ~8 ms, respond to generated terrain
and other spheres, and support restitution and sensors. A sweep along X builds
pair candidates before impulses modify positions. Contacts describe the last
substep's sphere overlaps. Set `active=False` to disable a body. `raycast` returns
the nearest active sphere hit, including exit hits for rays starting inside.

The solver is discrete, frictionless and has no angular motion. Terrain contact
uses height directly beneath the center plus sphere radius, an approximation on
slopes. Terrain contacts are not included in the sphere contact list. Large,
dense physics worlds need a different solver; the example caps thrown balls at
128. Only active local physics islands should be simulated for large worlds.

`Engine3D` calls `Game3D.update(input,dt)` at a fixed rate, then
`Game3D.draw(device,alpha)` and presents. The game controls all render passes.
Input edges survive frames with no update and are consumed after the first
update. P toggles pause; focus loss pauses; Escape exits. A bounded catch-up
clock prevents unbounded simulation work. `frame_limit` supports automated runs.
The device remains alive after `run` so games can release their asset caches.

## Source map

| Module | Responsibility |
| --- | --- |
| `transform3d`, `spatial` | Math, bounds, rays, frustum |
| `scene3d`, `editor3d` | Hierarchy, serialization, editing, navigation |
| `mesh`, `assets3d` | CPU meshes, OBJ import, cached GPU assets |
| `graphics3d`, `native/mojo/runtime.mojo`, `shaders/` | Graphics ownership, Vulkan passes |
| `world3d`, `partition` | Procedural terrain and authored cell residency |
| `physics3d`, `engine3d` | Simulation and game lifecycle |

## Imported collision

`TriangleMesh3D(mesh, matrix)` builds a static triangle BVH using Float64 world
coordinates. `TriangleMesh3D.load(path, matrix)` validates cooked BVH topology,
bounds and dependencies before applying the transform. `CollisionWorld3D.add_mesh`
and `add_collider` register geometry explicitly; collision ownership is separate
from render handles. Capsule sweeps, stepping, recovery and moving supports work
with boxes and triangle meshes. Removing a mesh frees its geometry and invalidates
its generational support handle.

`CollisionStreamer3D.update(world, assets, collision)` replaces complete cell
revisions and evicts geometry with scene cells. `ready(world, assets, x, z)` reports
whether collision matches the current scene and asset revisions. The Atlas editor
checks destination-cell readiness before stepping its character. Applications
must apply the same loading policy to keep characters out of unloaded collision.
The manager bounds cells processed per call and live collision payload. Its file
reads and validation run on the caller; a large cell can exceed a frame budget.
Temporary preparation and binary-read buffers are outside the live payload budget.

Cooked rigs describe bind-pose geometry. Use explicit static collision for scenery
and character capsules for animated actors; a cooked collider does not track skin
deformation automatically.
