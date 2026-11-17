#!/bin/bash
# fpblot2.sh: build fpframes copies of the baseline (git HEAD~1's selfhost, in build/fpb-base) and of selfhost/, run
# each on the blot2 copy one at a time, and compare the state lines (a hash every 2,000 frames).
W=/home/user/goose-to-wasm; cd $W; T=bench/results/2026-11-14/blot2-lifetimes/tools; B=$W/build/blot2-head/compiler-goose/src
rm -rf build/fpb-base build/fpb-cand; mkdir -p build/fpb-base build/fpb-cand
git archive ${BASE:-HEAD~1} selfhost | tar -x -C build/fpb-base; cp -r selfhost build/fpb-cand/selfhost
for v in base cand; do
  python3 $T/instrument.py build/fpb-$v/selfhost fpframes >/dev/null
  G=$W/build/q-r2/bootstrap/bin/goose bash build/tools/mk.sh build/fpb-$v/selfhost build/exp/fpb-$v.exe 2>&1 | grep "error\|built"; rm -f build/exp/fpb-$v.exe.c
done
for v in base cand; do
  ( cd $B && /usr/bin/env bash -c "time $W/build/exp/fpb-$v.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check" > $W/build/tmp/sp/fpb-$v.out 2> $W/build/tmp/sp/fpb-$v.err; echo "$v rc=$?" )
  grep -c LIFEFP build/tmp/sp/fpb-$v.err; grep real build/tmp/sp/fpb-$v.err
done
grep LIFEFP build/tmp/sp/fpb-base.err > build/tmp/sp/fpb-base.fp; grep LIFEFP build/tmp/sp/fpb-cand.err > build/tmp/sp/fpb-cand.fp
cmp build/tmp/sp/fpb-base.fp build/tmp/sp/fpb-cand.fp && echo BLOT2-FINGERPRINTS-SAME $(wc -l < build/tmp/sp/fpb-cand.fp) lines
grep -c "error" build/tmp/sp/fpb-base.out build/tmp/sp/fpb-cand.out; cmp build/tmp/sp/fpb-base.out build/tmp/sp/fpb-cand.out && echo BLOT2-OUTPUT-SAME
