#!/usr/bin/env bash
set -euo pipefail
root="$(pwd)"
out="$root/build/neon-shadow-scheduler"
mode="$1"
limit="$2"
dest="$out/$mode-$limit"
mkdir -p "$dest"
git archive 204ae57 ':(glob)selfhost/*.goose' stdlib native | tar -x -C "$dest"
python3 "$out/probe.py" "$dest/selfhost/checker_lifetimes.goose" "$mode"
python3 "$root/bench/results/2026-11-19/lifetime-store-delivery/tools/fingerprint.py" "$dest" --class-limit "$limit"
sed -i '0,/^import os;$/ { /^import os;$/d; }' "$dest/selfhost/checker_lifetimes.goose"
cd "$dest"
ulimit -s 262144
"$root/build/neon-implementation/own/build-1/compiler-native" selfhost/main.goose --stdlib stdlib -O2 --target native -o compiler.c
clang -w -O0 -std=gnu11 compiler.c -lm -ldl -pthread -o compiler
