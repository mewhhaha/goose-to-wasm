#!/usr/bin/env bash
# Build diagnostic copies. The compiler and project manifests pin the two source trees.
set -euo pipefail
tools=$(dirname "$(realpath "$0")")
repo=$(git -C "$tools" rev-parse --show-toplevel)
compiler=$(realpath "$1")
workload=$(realpath "$2")
stage=$(realpath -m "$3")
mkdir "$stage"
ulimit -s 262144
emit=("$compiler/emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2)
wide=(--wasm-memory64 --wasm-max-pages 262144)
target=(selfhost/main.goose --stdlib stdlib --target wasm-direct -O2)
scratch_source() {
    mkdir "$2"
    cp -a "$1/selfhost" "$2/"
    ln -s "$1/native" "$1/stdlib" "$2/"
}

scratch_source "$workload/source" "$stage/name-src"
python3 - "$stage/name-src/selfhost/codegen.goose" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
src = p.read_text()
marker = "else if p.debug {\n        var name_count"
assert src.count(marker) == 1
p.write_text(src.replace(marker, "else {\n        var name_count"))
PY
(cd "$stage/name-src" && "${emit[@]}" "${wide[@]}" -o "$stage/name-emitter.wasm")
name_module() {
    (cd "$1" && node --stack-size=65500 "$repo/scripts/run_wasm.mjs" "$stage/name-emitter.wasm" -- "${target[@]}" "${wide[@]}" -o "$2")
}
name_module "$compiler/source" "$stage/named.wasm"
(cd "$compiler/source" && "${emit[@]}" "${wide[@]}" --wasm-region-stats -o "$stage/stats.wasm")
(cd "$workload/source" && GOOSE_REGION_PROFILE="$stage/regions.txt" "$repo/.venv/bin/python" "$repo/scripts/run_wasmtime.py" "$stage/stats.wasm" -- "${target[@]}" "${wide[@]}" -o "$stage/stats-output.wasm")
cmp "$stage/stats-output.wasm" "$workload/build-1/compiler.wasm"
(cd "$compiler/source" && "${emit[@]}" "${wide[@]}" --wasm-region-profile "$stage/regions.txt" -o "$stage/profiled64.wasm")
(cd "$compiler/source" && "${emit[@]}" --wasm-max-pages 65535 --wasm-region-profile "$stage/regions.txt" -o "$stage/profiled32.wasm")
scratch_source "$compiler/source" "$stage/reference-src"
(cd "$stage/reference-src" && patch -p1 < "$tools/adjacent.patch" && "${emit[@]}" "${wide[@]}" -o "$stage/reference64.wasm")
name_module "$stage/reference-src" "$stage/reference-named.wasm"
PYTHONPATH="$repo/scripts" "$repo/.venv/bin/python" - "$stage" "$compiler" <<'PY'
from pathlib import Path
import sys
import wasmtime
from run_wasmtime import create_hosted_config, create_engine

stage, compiler = map(Path, sys.argv[1:])
for name, plain, output in (("named.wasm", compiler/"build-1/compiler.wasm", "compiler.cwasm"),
                            ("reference-named.wasm", stage/"reference64.wasm", "reference.cwasm")):
    data = (stage/name).read_bytes()
    assert data.startswith(plain.read_bytes())
    cfg = create_hosted_config()
    cfg.profiler = "perfmap"
    cfg.cache = True
    engine = create_engine(cfg)
    (stage/output).write_bytes(wasmtime.Module(engine, data).serialize())
PY
