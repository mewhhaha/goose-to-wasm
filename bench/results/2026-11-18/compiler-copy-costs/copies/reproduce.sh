#!/usr/bin/env bash
# From the repository root, supply the two compiler stages, frozen workload stage,
# naming compiler from the baseline profile, native reference output, and scratch dir.
set -euo pipefail
repo=$(pwd)
src=$(cd "$(dirname "$0")" && pwd)
before=$(realpath "$1")
after=$(realpath "$2")
work=$(realpath "$3")
namer=$(realpath "$4")
expected=$(realpath "$5")
out=$(realpath -m "$6")
mkdir -p "$out"
python="$repo/.venv/bin/python"
export TMPDIR="$out"
cpu=${PROBE_CPU:-2}
ulimit -s 262144
taskset -c "$cpu" cargo build --locked --release --manifest-path "$src/Cargo.toml" --target-dir "$out/target" -j1
decoder="$out/target/release/wasm-copy-sites"
taskset -c "$cpu" "$python" "$src/control.py" "$decoder" > "$out/control.json"
flags=(selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144)
for label in before after; do
    stage=$before
    if [[ $label == after ]]; then stage=$after; fi
    dir="$out/$label"
    mkdir -p "$dir"
    named="$dir/named.wasm"
    (cd "$stage/source" && taskset -c "$cpu" node --stack-size=65500 "$repo/scripts/run_wasm.mjs" "$namer" -- "${flags[@]}" -o "$named")
    taskset -c "$cpu" "$decoder" "$named" > "$dir/sites.txt"
    taskset -c "$cpu" "$python" "$src/instrument.py" "$named" "$dir/sites.txt" "$dir/counters.wasm"
    for mode in check emit; do
        taskset -c "$cpu" "$python" "$src/measure.py" "$repo" "$stage" "$work" "$named" "$dir/counters.wasm" \
            "$expected" "$dir/$mode.json" --mode "$mode" --cpu "$cpu"
    done
    "$python" "$src/summarize.py" "$dir" > "$dir/summary.json"
done
"$python" "$src/compare.py" "$out/before" "$out/after" > "$out/comparison.json"
taskset -c "$cpu" "$python" "$src/lowering.py" "$repo" "$before/build-1/compiler-native" "$out/before/named.wasm" "$out/before" > "$out/lowering.json"
focus="$out/post-sites"
mkdir -p "$focus"
taskset -c "$cpu" "$python" "$src/instrument.py" "$out/after/named.wasm" "$out/after/sites.txt" "$focus/counters.wasm" --detail life_contains life_alt_overlaps cg_function
taskset -c "$cpu" "$python" "$src/measure.py" "$repo" "$after" "$work" "$out/after/named.wasm" "$focus/counters.wasm" \
    "$expected" "$focus/check.json" --mode check --cpu "$cpu"
taskset -c "$cpu" "$python" "$src/remaining.py" "$repo" "$out/after/named.wasm" "$after" "$out/after" \
    "$focus/check.json" "$out/after/emit.json" > "$out/remaining.json"
