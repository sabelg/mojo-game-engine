# mojo_game API guide

Start with the [workspace README](../README.md) for build commands and a minimal
game, or [Orb Collector](../examples/orb_collector.mojo) for a complete example.

## Loop and input

`Engine.run(game)` polls events, calls `Game.update(input, dt)` zero or more
times at a fixed rate (60 Hz by default), clears the render target, calls
`Game.draw(window, alpha)`, and presents. `alpha` is the remaining fractional
step; retain previous/current positions in your game to interpolate drawing.
`Game.draw` borrows game state immutably. `P` pauses/resumes; Escape exits.
Input edges are retained if a frame has no update, then consumed by the first
update. Held keys remain visible to every update. Engine-level P handling
consumes that press. Poll deltas are capped to 50 ms. `FixedClock` independently
bounds catch-up to eight steps and records discarded seconds in `dropped`.

For a custom loop use `Window.poll()`, update state, `begin()`, draw, and
`present()`. Poll normally resets input edges; pass `preserve_edges=True` and
call `input.clear_edges()` yourself for fixed-step scheduling.

`down(scan)`, `pressed(scan)`, `released(scan)`, and `axis(negative, positive)`
use SDL scancodes. A=4, D=7, W=26, S=22, arrows=79/80/81/82, Space=44,
Enter=40, R=21, M=16, Escape=41. Out-of-range scancodes are ignored. Repeat
events do not generate extra press edges. Focus loss clears held keys, reports
releases, and pauses started games. Mouse coordinates are logical canvas
coordinates; `mouse_down(1/2/3)` tests left/middle/right buttons. Mouse buttons
currently expose held state only. One event-polling window per process is
supported.

## Entities and components

Create an entity with `world.create()`. Use `store.set(world, entity, value)`,
`store.get(world, entity)`, `store.has(...)`, and `store.remove(...)`.
`get` returns a copy: modify it and call `set` to write changes back.
Components can be any `Copyable & Deinitable` type. Keep stores paired with the
World that created their IDs; IDs do not identify different World instances.

Destroying an entity invalidates its generation immediately. A new entity can
reuse the slot without inheriting components. `world.entities()` gives a
snapshot, so destroying entities during iteration is safe. Call
`store.collect(world)` after destruction to release stale component values.
The World does not own stores and cannot clear them automatically.

## Physics

The additive 3D rigid-body foundation exports `MassProperties3D` and
`RigidBody3D` for checked principal inertia and linear/angular impulses. R02a adds
transactional force/torque accumulation and explicit single-body pose integration
(qualified finite CPU numerical profile). It does
not replace the existing sphere or 2D simulation. See the
[native Mojo physics roadmap and first numerical qualification](../docs/PHYSICS_ROADMAP.md).

`Body2D(position, half, mass=1, restitution=0, sensor=False)` stores center,
half extents, velocity, inverse mass, bounce and sensor state. A zero mass is
static. Dimensions/mass must be nonnegative, restitution must be in [0,1].
`Physics2D(gravity)` defaults to downward gravity `(0,980)` in pixels/s².
`physics.step(world, bodies, dt)` integrates dynamic bodies, detects AABB
contacts, corrects penetration and applies normal impulses. Use a fixed dt.

`contacts` is replaced every step and contains entity IDs, a normal from A to
B, and penetration depth. Sensors generate contacts with no collision
response. Touching edges count as contacts. Contacts are per-step overlaps,
not enter/exit events. Validate IDs before processing if earlier handlers may
have destroyed an entity. Physics and drawing share game-owned state; the
engine does not automatically synchronize components with render objects.

## Scenes, events and animation

`SceneStack(initial=0)` holds game-defined IDs. `push(id)`, `replace(id)` and
`pop()` queue a transition; `commit()` applies it and reports whether it was
applied. The last request before commit wins. Popping the root does nothing.
Dispatch `current()` in your game; scene data and lifecycle callbacks belong
to the game. A pushed overlay leaves underlying game-owned scene state intact.

`EventQueue[T].emit(value)` appends; `drain()` transfers all pending events in
FIFO order and leaves an empty queue. Processing can emit the next batch.

`Animation(first, count, fps, looping=True)` advances with `update(dt)` and
returns the sprite sheet frame index from `frame()`. A one-shot animation
holds its last frame and sets `finished`. `restart()` resets playback.

## Rendering and images

Window drawing uses a fixed 1100×760 logical canvas. `box`, `line`, and `text`
provide 2D primitives and a built-in bitmap font. `load_bitmap(path)` loads a
BMP and returns a texture index owned by that Window. Load once, outside the
frame loop. `sprite(id, source_rect, destination_rect, angle=0)` draws a sheet
region, with rotation in degrees. `Rect` fields are Int32. Texture IDs remain
valid until window close; textures are released together during close.
`snapshot(path)` saves a BMP of the current renderer target, before present.

For 3D: draw into `window.raster`, call `window.present_3d()`, then draw UI and
call `window.present()`. `begin()` clears both depth and color buffers.
The CPU rasterizer uses focal length 720 and near/far planes 8/2800.
`Camera` stores origin, eye offset and orthonormal forward/right/up axes.
`Camera.world()` wraps world positions in a 2400-unit space; `relative()`
converts already-relative positions without wrapping. Geometry helpers build
procedural meshes, with no associated collision shapes.

## Audio and ownership

`SynthAudio.trigger_laser()` and `trigger_explosion()` start synthesized
effects. Call `update(speed, thrust, active, toggle_mute)` to feed playback.
`SynthAudio(False)` disables device creation; `synthesize(speed, thrust,
count, active=True)` returns Int16 mono samples at 22050 Hz for offline use.
Unavailable audio devices fall back to silence. Muting/pausing clears queued
audio; a custom game must pass its own activity state to audio updates.

Window, Raster texture, and audio resources clean up automatically. Explicit
`close()` is idempotent. Close audio before the window for deterministic
shutdown. Window texture handles and platform methods must not be used after
close. SDL's C ABI bindings target Linux x86-64. The package links to SDL3;
no Python runtime is required.
