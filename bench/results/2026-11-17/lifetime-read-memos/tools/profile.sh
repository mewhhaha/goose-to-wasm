#!/bin/bash
# profile.sh WORKDIR [N]: build WORKDIR/selfhost with frame pointers, sample its self-check of selfhost/, print the top N.
W=/home/user/goose-to-wasm; cd $W; D=$1; N=${2:-30}; T=bench/results/2026-11-15/lifetime-walks-and-memos/tools
G=$W/build/q-r2/bootstrap/bin/goose bash build/tools/mk.sh $D/selfhost build/exp/prof.exe -fno-omit-frame-pointer -g 2>&1 | grep "error\|built"
build/exp/prof.exe $D/selfhost/main.goose --stdlib stdlib --check --wasm-stats build/exp/prof.exe.stats.json >/dev/null 2>&1
PROF_OUT=build/tmp/sp/prof.out LD_PRELOAD=$W/build/tools/prof.so build/exp/prof.exe selfhost/main.goose --stdlib stdlib --check
python3 $T/report.py build/exp/prof.exe build/tmp/sp/prof.out $N 2>&1 | cut -c1-150
