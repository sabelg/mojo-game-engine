# Atlas upgrade migration and limits

This upgrade keeps the declared package version at 0.1.0. It is a development
candidate; the proposed roadmap releases are qualification gates, not published
versions. Build the engine and extracted SDK from the same source generation.

## Existing projects

1. Back up the project directory before migrating saved authoring data. Open it
   through `WorldStore`/`WorldEditor`; stable persistent IDs, scene migration and
   grouped redo recovery are handled there. Do not rewrite transaction files by
   hand or run two writers against the same world. Recovery preserves the last
   committed transaction and reports invalid data.
2. Rebuild the compiled Mojo API and native archive together using
   `pixi run --locked bash scripts/build.sh`. The source fingerprint check rejects
   stale combinations. The public native frame remains 448 bytes and the ABI
   fixture checks 1183 fields/layout values. Private rendering data has changed;
   old archives must not be mixed with newly generated shaders.
3. Recook source assets before enabling new foliage or HLOD policies. Existing
   binary/text material rows load; foliage adds binary row kind 5 and three text
   fields. HLOD metadata uses ATLASB2 kind 8. Keep the matching immutable generation
   and dependencies together. Publication replaces the root manifest only after
   validation; automatic generation garbage collection is not provided.
4. Use the binary asset manifest for `HLOD3D`, load its matching source scene and
   update the scene revision after edits. Each scene owns its HLOD cache. A source
   fingerprint, transform, material or asset revision mismatch selects original
   geometry. Cooking proxies is opt-in; arbitrary editor/prefab edits do not recook
   them automatically.
5. For timed terrain LOD fades, pass elapsed seconds to
   `WorldStreamer.update(device, camera, dt)` and choose `transition_seconds` in
   0..2. The default duration is zero. Residency includes retained transition
   payloads; a paint revision that would exceed the configured budget fails without
   changing the current layer/revision. Retry after the active fade retires.
6. Treat transform previews as rendering overrides. Commit once through
   `WorldEditor.commit_preview`; cancel on stale identities, unloaded cells or
   changed ancestors. Saving during a drag preserves the authored transform.

The editor/reference example enables four shadow cascades and HDR/SH lighting.
Use its `--legacy-lighting` option for the previous color pipeline. Static LOD
transitions can be disabled; HLOD's `enabled=False` compares original geometry,
and `transitions=False` selects immediate switches.

## Qualified scope and known limits

Regression evidence covers Linux ARM64 with Mesa lavapipe and NVIDIA GB10,
including synchronization validation, MSAA 1/4, one/two frame banks, isolated
editor play, SDK builds and independent game smoke checks. Xvfb exercises actual
surfaces and swapchain recreation; it does not qualify visible desktop usability.
See [Validation](VALIDATION.md) for frozen source identities and measured runs.
`scripts/qualify-sdk.py --window` now repeats clean SDK builds, synchronization
checks, legacy/HDR surfaces and an independent starter; its CI invocation still
requires the runner's compiler, driver/validation layers and Xvfb dependencies.

- Runtime TAA, Vulkan motion/history attachments and high-frequency mirror
  environment maps are not implemented. The temporal script is an offline study.
- Static HLOD excludes animated/morph content and wind-driven foliage. Both LOD
  levels render during a fade; deterministic coverage can remain visible.
- Foliage wind expands render bounds; collision stays at authored geometry.
- glTF BLEND, required unsupported extensions, texture transforms and animated
  morph weights are rejected. OBJ/glTF cooking has bounded files, geometry and
  estimated work; the estimate is not an RSS guarantee or exhaustive fuzz audit.
- Scene/cache edits require revision changes. The controller/navigation facilities
  do not provide a general rigid-body solver, networking or multiplayer.
- Floating desktop docking, OS drag/drop, cross-vendor/platform qualification,
  representative dense-world targets, overnight endurance and full resource/leak
  audits remain open release gates. Headless fixture timings do not establish the
  proposed 16.7 ms reference-world deadline.

The source SDK deliberately excludes game content. Artifact checksums identify
the local candidate and evidence; they are not a published release signature.
