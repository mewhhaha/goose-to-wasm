#!/usr/bin/env bash
set -euo pipefail
root="$(pwd)"
out="$root/build/neon-shadow-scheduler"
emitter="${GOOSE_EMITTER:-$root/build/neon-implementation/own/build-1/compiler-native}"
profile="${GOOSE_LAYOUT_PROFILE:-$root/bench/results/2026-11-21/shared-emitters/training.profile}"
for mode in control shadow validation; do
    dest="$out/$mode"
    mkdir -p "$dest"
    git archive 204ae57 ':(glob)selfhost/*.goose' stdlib native | tar -x -C "$dest"
    python3 "$out/probe.py" "$dest/selfhost/checker_lifetimes.goose" "$mode"
    (
        cd "$dest"
        "$emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
            --wasm-bundled-host --wasm-initial-pages 65535 --wasm-max-pages 65535 \
            --wasm-region-profile "$profile" -o compiler.wasm
    )
done
