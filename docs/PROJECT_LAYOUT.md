# Engine and game boundaries

Atlas is the project root: `mojo_game/`, `native/mojo/`, `shaders/`, `examples/`, generic `tests/`, and engine-only build/package tooling. Engine source imports no game modules and carries no game audio path list. Asset preparation, stereo WAV sample loading, controllers and rendering have generic `mg_*` native exports; games supply their own content paths. Audio has 15 sample slots and 12 voices per process.

Yo Frankie is `games/yo-frankie/`: `src/main.mojo`, `frankie/`, `assets/`, `art/`, `third_party/`, `saves/`, `tests/`, `docs/`, `scripts/`, its own Pixi manifest and lock, and its own ignored `build/`. Existing save files moved with the game. Existing root build outputs remain historical evidence; new reports are written in the game build directory.

The dependency points from the game to Atlas. The game resolves `ATLAS_ENGINE_ROOT`, an extracted `engine/` SDK, or the repository's engine root. Its build checks engine fingerprints, includes the compiled `mojo_game.mojoc`, and copies/links a fingerprinted native archive. The game never owns an engine source copy during normal repository development. Engine build/package operations do not require the game directory.

`build/mojo-game-source.tar.gz` is a reusable engine source SDK with a checksum manifest and no game data. `games/yo-frankie/build/yofrankie-vulkan-source.tar.gz` contains the game plus that explicit engine source dependency under `engine/`. Builds remain native Linux ARM64/x86-64.

Create another game with `python3 scripts/new-game.py /absolute/path/to/new-game`. The independent starter uses Orb Collector, requires no Yo Frankie assets, and accepts another engine checkout via `ATLAS_ENGINE_ROOT`. Its build and game output stay in its own directory. The engine SDK is source, not a redistributable standalone binary runtime.

Root `scripts/*frankie*` commands forward for compatibility. Prefer running game commands from the game directory, including benchmarks: relative outputs resolve to that project's `build/`.
