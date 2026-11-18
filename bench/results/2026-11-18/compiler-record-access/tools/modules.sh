#!/usr/bin/env bash
# Build the four forms of the candidate compiler and calibrate the 32-bit layouts.
set -euo pipefail
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
compiler_stage=$(realpath "$1")
project_stage=$(realpath "$2")
output=$(realpath -m "$3")
mkdir "$output"
ulimit -s 262144
compiler="$compiler_stage/build-1/compiler-native"
emit=(selfhost/main.goose --stdlib stdlib --target wasm-direct -O2)
wide=(--wasm-memory64 --wasm-max-pages 262144)
(cd "$project_stage/source" && "$compiler" "${emit[@]}" "${wide[@]}" -o "$output/expected.wasm")
cd "$compiler_stage/source"
"$compiler" "${emit[@]}" "${wide[@]}" -o "$output/general64.wasm"
cmp "$output/general64.wasm" "$compiler_stage/build-1/compiler.wasm"
"$compiler" "${emit[@]}" "${wide[@]}" --wasm-bundled-host -o "$output/bundled64.wasm"
"$compiler" "${emit[@]}" "${wide[@]}" --wasm-bundled-host --wasm-region-stats -o "$output/stats.wasm"
(cd "$project_stage/source" && GOOSE_REGION_PROFILE="$output/regions.txt" "$repo/.venv/bin/python" "$repo/scripts/run_wasmtime.py" "$output/stats.wasm" -- "${emit[@]}" "${wide[@]}" -o "$output/calibration.wasm")
cmp "$output/calibration.wasm" "$output/expected.wasm"
narrow=(--wasm-max-pages 65535 --wasm-region-profile "$output/regions.txt")
"$compiler" "${emit[@]}" "${narrow[@]}" -o "$output/general32.wasm"
"$compiler" "${emit[@]}" "${narrow[@]}" --wasm-bundled-host -o "$output/bundled32.wasm"
