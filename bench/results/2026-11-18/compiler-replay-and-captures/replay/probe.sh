#!/usr/bin/env bash
# probe.sh RELEASE_EMITTER FROZEN_PROJECT_DIR EMPTY_STAGE counts|stamp|detail|group
set -euo pipefail
emitter=$(realpath "$1")
work=$(realpath "$2")
stage=$(realpath -m "$3")
mode=$4
evidence=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$evidence" rev-parse --show-toplevel)
ulimit -s 262144
mkdir "$stage"
git -C "$repo" archive f61fe052cb69df83dc04a87088fefb7a82539291 selfhost native stdlib | tar -x -C "$stage"
cd "$stage"
case "$mode" in
    counts) patch -s -p1 < "$evidence/counts.patch";;
    group) patch -s -p1 < "$evidence/group-counts.patch";;
    stamp|detail)
        patch -s -p1 < "$evidence/selected.patch"
        patch -s -p1 < "$evidence/$mode-shadow.patch";;
    *) exit 2;;
esac
flags=(selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144)
"$emitter" "${flags[@]}" -o "$stage/probe.wasm"
(cd "$work" && "$repo/.venv/bin/python" "$repo/scripts/run_wasmtime.py" "$stage/probe.wasm" -- selfhost/main.goose --stdlib stdlib --check)
if [[ $mode == stamp ]]; then
    sed -i 's/LIFE_CONCRETE_FRAMES: i64 = 4096/LIFE_CONCRETE_FRAMES: i64 = 64/' selfhost/checker_lifetimes.goose
    "$emitter" "${flags[@]}" -o "$stage/class.wasm"
    (cd "$work" && "$repo/.venv/bin/python" "$repo/scripts/run_wasmtime.py" "$stage/class.wasm" -- "$evidence/class-read.goose" --stdlib stdlib --check)
fi
