#!/usr/bin/env bash
set -euo pipefail
root="$(pwd)"
out="$root/build/neon-shadow-scheduler"
emitter="${GOOSE_EMITTER:-$root/build/neon-implementation/own/build-1/compiler-native}"
profile="${GOOSE_LAYOUT_PROFILE:-$root/bench/results/2026-11-21/shared-emitters/training.profile}"
runner="${WASMTIME_RUNNER:-$root/host/rust/target/release/goose-wasmtime}"
frozen="${WORKLOAD_SOURCE:-$root/build/next-small-release/own/source}"
limit="${1:-4096}"
for mode in control audit; do
    dest="$out/$mode-$limit"
    (
        cd "$dest"
        "$emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
            --wasm-bundled-host --wasm-initial-pages 65535 --wasm-max-pages 65535 \
            --wasm-region-profile "$profile" -o compiler.wasm
    )
    (
        cd "$frozen"
        "$runner" "$dest/compiler.wasm" --cache "$dest/compiler.cwasm" -- \
            selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
            --wasm-memory64 --wasm-max-pages 262144 -o "$dest/frozen.wasm" \
            >"$dest/frozen.stdout" 2>"$dest/frozen.stderr"
    )
done
cmp "$out/control-$limit/frozen.stderr" "$out/audit-$limit/frozen.stderr"
cmp "$out/control-$limit/frozen.wasm" "$out/audit-$limit/frozen.wasm"
sha256sum "$out"/{control,audit}-"$limit"/{compiler,frozen}.wasm
awk '/^shadow|^mismatch/' "$out/audit-$limit/frozen.stdout"
