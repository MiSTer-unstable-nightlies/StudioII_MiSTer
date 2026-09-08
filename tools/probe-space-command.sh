#!/usr/bin/env bash
# Select the canonical database title; cartridge filenames may change.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/tools/game-start-sweep.py" --run --machine visicom --match "Space Command" "$@"
