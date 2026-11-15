#!/bin/bash
# Stage names are this session's build names: base-prog = 86f7a18, eff4 = 60871b7, fn1 = 826e892,
# rp2 = 48c4cf4, m1 = b411c7f without its 32-bit fields, m2 = b411c7f, m3 = f96470c, m4 = 2cc4840,
# m5 = a7ac66b, m6 = fe05443. Paths are this session's build/ layout.
# stagecheck.sh STAGE...: for each stage source build/stages/STAGE.goose, build
# a fingerprint compiler and compare its analysis state with the baseline's on
# the self-check and on every conformance source.
W=/home/user/goose-to-wasm
cd $W
for st in "$@"; do
  d=build/exp/fps-$st; rm -rf $d; mkdir -p $d; cp selfhost/*.goose $d/; cp build/stages/$st.goose $d/checker_lifetimes.goose
  python3 build/tools/instrument.py $d fingerprint || { echo "$st INSTRUMENT FAILED"; continue; }
  build/tools/mk.sh $d $d.exe > build/runs/fps-$st.build.log 2>&1 || { echo "$st BUILD FAILED"; continue; }
  (cd build/tmp/stats && $W/$d.exe sources/main.goose --stdlib $W/stdlib --check 2>&1 | grep LIFEFP > $W/build/runs/fps-self-$st.txt)
  if cmp -s build/runs/fp-self-base.txt build/runs/fps-self-$st.txt; then echo "$st self: identical ($(wc -l < build/runs/fps-self-$st.txt) fingerprints)"; else echo "$st self: DIFFERS"; fi
  rm -rf build/fps-out-$st
  echo "$st corpus: $(python3 build/tools/fpcompare.py $W/build/exp/fp-base.exe $W/$d.exe $W/build/fps-out-$st --jobs 3 2>&1 | tail -1)"
done
echo DONE
