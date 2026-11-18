#!/usr/bin/env bash
# corpus.sh RELEASE_EMITTER FROZEN_PROJECT_DIR EMPTY_STAGE
set -euo pipefail
emitter=$(realpath "$1")
work=$(realpath "$2")
stage=$(realpath -m "$3")
evidence=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$evidence" rev-parse --show-toplevel)
mkdir "$stage"
cd "$stage"
git -C "$repo" archive f61fe052cb69df83dc04a87088fefb7a82539291 selfhost native stdlib | tar -x
patch -s -p1 < "$evidence/counts.patch"
ulimit -s 262144
"$emitter" selfhost/main.goose --stdlib stdlib --target native -O2 -o probe.c
clang-23 -O0 -w -std=gnu11 probe.c -lm -ldl -pthread -o probe-native
mkdir upstream
archive=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upstream"]["archive"])' "$repo/tests/conformance/cases.json")
tar xf "$repo/$archive" -C upstream
mkdir -p upstream/stdlib
cp -a "$work/stdlib/." upstream/stdlib/
python3 "$evidence/corpus-counts.py" "$repo" "$stage/probe-native" "$stage/upstream" "$work/stdlib" "$stage/corpus.json" --workers 4
