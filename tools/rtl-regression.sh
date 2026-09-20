#!/usr/bin/env bash
# Rebuild and run the focused RTL regression suite from any working directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

quiet_build() {
    local label=$1
    local log
    local status
    shift
    log=$(mktemp)

    if "$@" >"$log" 2>&1; then
        printf '%s: PASS\n' "$label"
        rm -f "$log"
        return 0
    fi

    status=$?
    printf '%s: FAIL\n' "$label" >&2
    cat "$log" >&2
    rm -f "$log"
    return "$status"
}

quiet_build "Headless model build" \
    make --no-print-directory -C "$ROOT/verilator" -B headless

quiet_build "CDP1802 LOAD test build" \
    make --no-print-directory -C "$ROOT/verilator" -B ./obj_dir_cpu_load/Vcdp1802

quiet_build "Palette test build" \
    make --no-print-directory -C "$ROOT/verilator" -B ./obj_dir_palette/Vstudio2_palette

"$ROOT/verilator/obj_dir_cpu_load/Vcdp1802"
"$ROOT/verilator/obj_dir_palette/Vstudio2_palette"
bash "$ROOT/tools/headless-smoke.sh"
