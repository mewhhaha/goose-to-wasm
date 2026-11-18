#!/usr/bin/env bash
# Sample a general memory64 compiler, appending function names without changing its code.
set -euo pipefail
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
compiler_stage=$(realpath "$1")
project_stage=$(realpath "$2")
expected=$(realpath "$3")
scratch=$(realpath -m "$4")
mkdir "$scratch"
ulimit -s 262144
cp -a "$compiler_stage/source/selfhost" "$scratch/"
ln -s "$compiler_stage/source/native" "$compiler_stage/source/stdlib" "$scratch/"
python3 - "$scratch/selfhost/codegen.goose" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
marker = "else if p.debug {\n        var name_count"
assert source.count(marker) == 1
path.write_text(source.replace(marker, "else {\n        var name_count"))
PY
flags=(selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144)
(cd "$scratch" && "$compiler_stage/build-1/compiler-native" "${flags[@]}" --wasm-bundled-host -o "$scratch/namer.wasm")
(cd "$compiler_stage/source" && node --stack-size=65500 "$repo/scripts/run_wasm.mjs" "$scratch/namer.wasm" -- "${flags[@]}" -o "$scratch/named.wasm")
"$repo/.venv/bin/python" "$repo/bench/results/2026-11-18/compiler-runtime-gap/tools/profile.py" "$compiler_stage" "$project_stage" "$scratch/named.wasm" "$scratch/post.json" --expected-emission "$expected" --cpu 5 --rounds 2
