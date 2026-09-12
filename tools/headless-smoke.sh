#!/usr/bin/env bash
# Run existing directed checks without building or accepting stale output.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for tool in make python3 timeout; do
    command -v "$tool" >/dev/null || { echo "error: missing $tool" >&2; exit 2; }
done
export HEADLESS_SIM="$ROOT/verilator/obj_dir_headless/Vtop"
[[ -x "$HEADLESS_SIM" ]] || { echo "error: missing headless model; build with make -C verilator headless" >&2; exit 2; }
if ! make -q -C "$ROOT/verilator" ./obj_dir_headless/Vtop; then
    echo "error: headless build is stale or cannot be checked; run make -C verilator headless" >&2
    exit 2
fi
mkdir -p "$ROOT/out"
REPORT=$(mktemp -d "$ROOT/out/headless-smoke.XXXXXXXX")
echo "Logs: $REPORT"
failed=0
run() {
    local name=$1
    shift
    if timeout --kill-after=5s "${HEADLESS_TIMEOUT:-120}s" "$@" >"$REPORT/$name.log" 2>&1; then
        echo "PASS $name"
    else
        local status=$?
        echo "FAIL $name (exit $status; see $REPORT/$name.log)"
        failed=1
    fi
}
run loader-input "$HEADLESS_SIM" --bios "$ROOT/rom/studio2.rom" --loader-check --quiet
run memory bash "$ROOT/tools/memdecode-test.sh"
run chip8 bash "$ROOT/tools/chip8-loader-test.sh"
run visicom bash "$ROOT/tools/visicom-loader-test.sh"
run tone bash "$ROOT/tools/tone-test.sh"
exit "$failed"
