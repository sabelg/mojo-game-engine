#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cc -std=c11 -O2 -Wall -Wextra -Werror -c native/frankie.c -o build/frankie.o
mojo build games/yo_frankie.mojo -I . -Xlinker build/libmojo_graphics.a -Xlinker build/frankie.o -Xlinker -lSDL2 -Xlinker -lvulkan -Xlinker -lm -o build/yo-frankie

mojo build tests/yofrankie.mojo -I . -o build/frankie-test
cc -std=c11 -O2 -Wall -Wextra -Werror tests/frankie_input.c build/frankie.o build/libmojo_graphics.a -lSDL2 -lvulkan -lm -o build/frankie-input-test
