# Production requirements still outstanding

The implemented engine is a foundation. A professional open-world engine needs
these additional milestones before it should be used as a shipping platform.

| Area | Next implementation | Acceptance criteria |
| --- | --- | --- |
| Streaming | Worker jobs, prioritized I/O, cancellation, upload staging | Repeatable frame-time/memory budgets during sustained travel and teleports |
| World authoring | Partition-aware editor, cross-cell moves, terrain edits, transactions | Save/reload a multi-cell world without lost references or edits |
| Asset pipeline | glTF, material/texture import, dependency manifests and build cache | Deterministic cooked assets with validation and incremental rebuilds |
| Rendering | GPU instancing, HLOD, cascaded shadows, antialiasing, image-based lighting | Visual regressions and benchmarks on supported GPU vendors |
| Animation | Skeletons, skinning, clips, blending and root motion | Reference pose/deformation tests and animation-driven sample character |
| Physics | Mature rigid-body solver, shapes, CCD, friction and constraints | Stress/stack/tunneling tests with fixed-step reproducibility |
| Gameplay | Navigation, character controller, spatial audio and save games | End-to-end playable open-world reference game |
| Editor | Gizmos, asset browser, dockable UI and project settings | Author/import/play/package workflow without source edits |
| Platforms | Platform abstraction and supported driver matrix | CI builds plus hardware smoke/performance tests on each target |
| Reliability | Fuzz parsers, resource leak checks, crash recovery, long-run soak | No corruption/leaks under malformed input and extended streaming sessions |

Networking, scripting, multiplayer replication and console support require
separate product requirements and are not implemented.
