#!/usr/bin/env bash
# Build one scratch probe. Use a fresh output path for each source and mode.
set -euo pipefail
source_tree=$(realpath "$1")
mode=$2
output=$(realpath -m "$3")
emitter=$(realpath "$4")
tools=$(dirname "$(realpath "$0")")
mkdir -p "$(dirname "$output")"
mkdir "$output"
cp -a "$source_tree/selfhost" "$output/"
ln -s "$source_tree/stdlib" "$source_tree/native" "$output/"
python3 "$tools/instrument.py" "$output" "$mode"
cd "$output"
ulimit -s 262144
"$emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144 -o probe.wasm
if [[ $mode == counts ]]; then
    "$emitter" selfhost/main.goose --stdlib stdlib --target native -O2 -o probe.c
    clang-23 -w -std=gnu11 -O1 probe.c -lm -ldl -pthread -o probe-native
fi
