# G02 GPU body lifecycle — bounded qualified prototype

On October 12, 2026, G02 passed source and precompiled-API GPU tests on NVIDIA
GB10 with the existing Mojo `1.2.0.dev2026092905` / MAX core
`26.7.0.dev2026092905` environment. The unchanged G01 numerical regression suite
also passed. Yo Frankie's opt-in review ran sixteen live GPU bodies for sixty
frames, reused a removed slot, rejected an old-generation update on GPU, checked
the CPU oracle after rendering and reported zero Vulkan validation errors.
This is Float64 correctness qualification, not a performance/release profile.

## API and ownership

`experimental.physics_gpu.lifecycle` supplies experimental `GpuWorld`,
`BodyHandle`, `BodyCommand` and `BodyPose`. The world owns persistent device SoA
current/scratch arrays, device active flags and UInt64 generation arrays. Slot
allocation (lowest free slot), liveness and stale-handle validation execute on
GPU. No host-side authoritative body registry is maintained. Host pose/handle
snapshots and caller-held handles are observations/requests, not registry authority.

A handle has `(slot: Int32, generation: UInt64, owner: UInt64)`. Generations start
at one, increase on removal and never wrap: a maximum-generation slot retires
permanently. A nonzero 64-bit Linux OS nonce seeds each world's device namespace;
this is a practical cross-world identity, not a security capability or guaranteed
globally unique identifier. Replay claims exclude that randomized namespace.

The instance is confined to one host caller and one ordered GPU context/stream.
All public operations complete before returning. `close()` waits for queued work
and makes further operations fail; repeated close is harmless. Owned buffers and
context reclaim at scope destruction, not immediately while a closed object is
still retained. There is no asynchronous external-buffer borrowing API.

```mojo
from std.collections import List
from mojo_game import RigidBody3D, MassProperties3D, Vec3
from experimental.physics_gpu.lifecycle import GpuWorld, BodyCommand

var world = GpuWorld()
var body = RigidBody3D(MassProperties3D.sphere(2, .5))
var create: List[BodyCommand] = [BodyCommand.create(body)]
var handles = world.submit(create)
var force: List[BodyCommand] = [BodyCommand.force(handles[0], Vec3(1, 0, 0))]
_ = world.submit(force)
var status = world.step(1.0/60)
# Observe/check status before publishing a simulation result.
var poses = world.poses()
world.close()
```

## Ordered transaction semantics

Capacity is 256 fixed slots and 256 commands per batch. `submit()` executes the
list in order on GPU scratch state/metadata. All commands commit together only
if every command succeeds. Failure raises with GPU status and command index;
current state, live flags and generations retain their pre-batch values. Failed
creates expose no tentative handles. Results contain committed create handles
in command order. Empty batches are no-ops. Pending commands cannot reference
a not-yet-returned creation via a temporary-handle API; that API is not supplied.

- `create(body)`: checked initial SI/COM state; GPU chooses the slot and returns
  its generation/namespace. Removal followed by creation can reuse the same slot.
- `remove(handle)`: GPU checks namespace, range, liveness and generation before
  clearing state and increasing generation or retiring an exhausted slot.
- `update(handle, body)`: replace pose, velocities and accumulators; GPU rejects
  mass/principal-inertia changes. Change that configuration through remove/create,
  which returns a new identity. Fixed bodies still require zero velocities;
  explicit pose updates are teleports, not a kinematic-motion implementation.
- `force(handle, force, torque)`: replace that body's accumulated force/torque.
  `all_forces(force, torque)` does the same for all active bodies at its position
  in the command list. These are set operations, not additive impulse commands.

Integration reuses immutable G01 math/limits, advances only active slots and
commits a whole step only on successful GPU validation. Inactive/retired slots
are skipped; invalid global dt/gravity/substep parameters reject even an empty
world. Successful integration consumes accumulators once. A failed step returns
a nonzero status without publishing partial poses.

## Host versus GPU validation and transfer accounting

Host validation covers closed ownership, command-count bounds and ordinary
`RigidBody3D.validate()` in create/update factories. Raw command fields can still
be malformed: GPU revalidates opcodes, body/material-independent state, immutable
mass/inertia, force finiteness and all handle identity/liveness rules. Stale and
out-of-range test packets reached GPU rejection; they were not filtered by a
host registry. Diagnostic status/command index are copied back to the host.

Current/scratch state and authoritative registry buffers allocate once per owner.
There is no per-frame full-state upload. Tests compared actual device pointer
stamps before/after repeated steps and command updates; both allocations stayed
identical. Full-state diagnostics copy GPU state to a separate device diagnostic
buffer before host mapping; they never map or write the authoritative state.
That diagnostic path is used after rendering, not as the game simulation input.

Command staging buffers resize only at a completed boundary when packet count
changes. Each logical command is 216 bytes (32-byte header, 184-byte payload).
A one-command force packet has 248 bytes of input-buffer storage including guards.
GPU registry/pose snapshots currently use fixed 20,512-byte output buffers for
all 256 slots; host consumers select active records. There is no active-list
compaction yet. Mapping may move entire buffers; actual DMA bytes/directions
have not been measured. Do not infer zero-copy or transfer throughput from these
logical/storage sizes. Rendering still stages poses through existing Vulkan upload.

At maximum command capacity, explicit device buffers total 231,688 bytes, below
the 16 MiB qualification cap. Driver/compiler/context and transient host mappings
are additional. Tests retain the 32 GiB available-memory reserve, finite sequential
stages and sampled temperature observation. No driver, hardware, thermal or H3
controls changed; no dependency/environment upgrade was needed for G02.

## Qualification and reproducible commands

Obtain the exclusive compute slot; keep H3 paused while running these:

```sh
python3 scripts/qualify-physics-lifecycle.py test --slot-confirmed
python3 scripts/qualify-physics-lifecycle.py packaged --slot-confirmed
python3 scripts/qualify-physics-lifecycle.py demo --slot-confirmed
python3 scripts/qualify-physics-gpu.py test --slot-confirmed  # unchanged G01 regression
```

Native builds use one compiler thread and a 180-second deadline; numerical and
render runs have 30-second bounds. Mojo precompile serializes non-elaborated
package code, exposes no thread-count switch and also has a finite 180-second
bound. Its separate `gpu_lifecycle_api.mojoc` alias avoids source-package import
ambiguity; the same lifecycle tests execute through that compiled path on GPU.
Normal Atlas compiled API and source SDK are not replaced by this artifact.

Passed fixtures: creation/removal/reuse; stale, zero-generation, range and foreign
handles; mixed FIFO update/force/remove/create; duplicate removal and whole-batch
rollback; malformed opcodes/state, nonfinite force and immutable-mass rejection;
body/command capacity; generation exhaustion; closed/scope cleanup; persistent
GPU addresses and 30/60/120 Hz CPU comparisons. The game review removes/reuses
slot 3 at frame 20, rejects the old update at frame 21, updates its replacement
at frame 35 and checks sixteen live bodies, current/scratch addresses and the
CPU oracle after sixty frames. The reused body renders blue.

Receipts: `build/physics-g02/{test,packaged,demo}-qualification.json` and
`games/yo-frankie/build/frankie-gpu-lifecycle-rendered.json`. Detailed source
hashes, commands, logs, observations, rollback and preservation checks are under
`/home/user/Documents/Codex/2026-10-12/task/physics-g02-20261012`.

This checkpoint supplies body lifecycle, not shape/collider ownership, contact
geometry, friction, joints, sleeping/islands, CCD, Float32 or direct CUDA–Vulkan
sharing. No performance, cross-platform replay or full campaign GPU migration
claim is made. G03 geometry/shape association is next and has not started.
