# Durable USD authoring workspaces

Use a workspace to resume editing named layers after closing Atlas. USD delivery
exports remain a separate operation: `save` and `package` compose owned edits into
one override; they do not preserve separate editing targets.

```sh
# New authoring project (the workspace parent must already exist):
pixi run usd-editor --source /path/art/scene.usda --workspace /path/project/workspace
# Resume without supplying the source again:
pixi run usd-editor --workspace /path/project/workspace
# Native API: save_workspace(destination=directory), open_workspace(source=directory)
# Batch CLI accepts a workspace directory as its positional source:
pixi run python scripts/usd-session.py /path/project/workspace --commands edits.json
```

In the editor, **S saves the workspace**, **F9 reopens its committed generation**,
**F6 exports a USD delivery** and **P packages USDZ**. The status line displays
whether workspace changes are saved. F9 requires a saved state. B creates a layer,
T selects an editing target and X clears it. The target, payload rules and timeline
metadata count as workspace changes. Undoing back to the saved state clears the
unsaved indicator. Closing does not implicitly save. Without `--workspace`, the
editor uses `workspace/` inside its `--output` directory. An existing workspace
must match an explicitly supplied `--source`.

## Format and bounds

`workspace.json` has `format: "atlas-usd-workspace"` and `version: 1` for local-only workspaces (`version: 2` adds owned sources). It records:

- The selected immutable `generation`, source path/byte length/SHA-256 and a
  complete dependency inventory, including unloaded payloads and textures.
- A separate session file and ordered named owned layer files, strongest first.
- `edit_target`, literal `load_rules` (`0` all, `1` only, `2` none), `prim_limit`
  and `history_policy: "empty-on-open"`.

Owned files use relative paths under `generations/g-<32 hex digits>/`. Symlinks,
absolute or escaping owned paths, duplicate names/paths, nested owned layer stacks
and unknown versions are rejected. Source/dependency paths are relative to the
workspace but may point outside it. Moving a directory containing both workspace
and source tree preserves those relationships; moving only the workspace can
require restoring its external dependencies at the recorded relative locations.

Limits are 1 MiB per manifest, JSON nesting 16, eight named layers plus session,
32 MiB combined authored layer content, 4,096 source files/load rules, 64 MiB per
source file and 256 MiB total source dependencies. Loaded prim limits are retained
(1–100,000). All owned files and source dependencies are checked before activation.
Missing or changed sources are reported; they are never overwritten or silently
accepted as the same source identity. A workspace does not embed external sources.

The native stage opens owned files into anonymous layers. It writes only new
generations, leaving original source files byte-identical. Changes to source files
or a workspace published by another session require reopening/resolving before
saving. Original source/reference files remain read-only. Owned copies can be
edited as described below.

## Owned source editing (M02)

**W** creates anonymous working copies of the complete filesystem USD layer graph.
**G** cycles the selected prim's contributing source/variant mappings. Root and
sublayer copies can also be selected with T. The target and concrete edit context
appear in the status line. Referenced targets require a concrete prim context;
ambiguous mappings require an explicit node from `source_targets(path=...)` in the
API. `select_source_layer(name=..., context=..., node=...)` selects that mapping.
Paths and numeric stage times map through the composition arc to the authored
spec and layer time, including sublayer/reference offsets and scales. Editing a
shared asset affects all its occurrences. Instance proxies are inspectable and
remain read-only. A key masked by a stronger opinion reports that status.

The watcher reports source conflicts without replacing edited copies. **F7**
accepts new source fingerprints while retaining copies; **F8** reloads originals
into the copies, discarding source-copy edits. Both actions are undoable. API:
`resolve_sources(action="keep_working"|"reload")`. A changed dependency graph
requires reimport. Save and delivery reject unresolved conflicts. Originals are
never overwritten. Reloading an existing workspace with changed sources rejects
it; resolve in the still-open session or restore the recorded source files.

Workspaces with source copies use **version 2**, retaining separate source files,
original identities, and the selected mapping. Version 1 remains supported.
Bounds include 64 source layers and 32 MiB combined session/local/source content.
Filesystem USD root, sublayers, references, payloads and selected variants are
supported; package-relative USDZ and custom-resolver sources require unpacking to
filesystem layers first. Exported USD uses an adjacent uniquely named source
directory; keep it with the delivery. USDZ embeds that graph and its dependencies.
Moving the whole project preserves relative asset relationships.

**C** reconciles per-occurrence IDs in the session even when a source copy is
selected. A persistent catalog reserves IDs hidden by unloaded payloads. Repeated
concrete occurrences get separate IDs. Proxy IDs derive from the instance-root
ID and relative descendant path; they survive restart but change on descendant
namespace changes. `identities` returns loaded, reserved and derived proxy rows.
Reconciliation is explicit; undo, workspace restart and delivery preserve its
session opinions. Source-copy scalar edits preserve that layer's sample map;
they do not seed keys from stronger composed opinions.

## Publication and recovery

A save takes a nonblocking OS writer lock, verifies the previously opened
generation, creates a unique generation, writes and synchronizes each owned file,
then synchronizes the generation directory. After validating files and source
fingerprints, it writes/synchronizes a temporary manifest and atomically renames it
over `workspace.json`, then synchronizes the project directory. The previous
complete workspace remains active until that manifest publication. Readers open
the generation named by the manifest; they ignore partial or orphan generations.

An error after publication can leave the new complete generation committed even
if the caller receives an error; reopen to determine the committed state. A crash
before a manifest is published in a new workspace leaves an uncommitted directory,
which can be saved again. Old generations and interrupted orphan generations are
retained. Automatic garbage collection and recovery of uncommitted edits are
outside this format. **Undo and redo history restart empty**; layer opinions and
strength, selected target and payload rules persist.

For regression fault injection only, `ATLAS_WORKSPACE_FAULT` accepts `kill:` or
`error:` followed by `generation_created`, `layers_synced`, `manifest_synced` or
`manifest_published`. The tests kill actual native processes at each boundary and
reopen from separate processes; error cases exercise the same publication path.

`tests/usd_workspace.py` checks conflicting named keys, payload rules, target and
source preservation across restart, relocation, stale writers, locking, malformed
manifests/checksums, dirty/undo state and publication faults.
`tests/usd_workspace_editor.py` tests the actual editor bridge across process
restart without Vulkan. `--smoke-workspace` exercises the native Mojo window and
its bridge with the software or hardware Vulkan driver.
`tests/usd_source_editing.py` covers mapped edits, conflicts, relocation and
USD/USDZ delivery; `tests/usd_identity_payloads.py` covers hidden reservations,
duplicate occurrences, read-only proxies and restart.

`--smoke-source` exercises working-copy target selection, scalar edits, identity
repair and workspace reopen in the native window without running a preview cook.
