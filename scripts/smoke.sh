#!/usr/bin/env bash
set -euo pipefail
build/platform-test
build/orb-collector --smoke
