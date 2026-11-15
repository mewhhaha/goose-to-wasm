#!/bin/bash
# Stage names are this session's build names: base-prog = 86f7a18, eff4 = 60871b7, fn1 = 826e892,
# rp2 = 48c4cf4, m1 = b411c7f without its 32-bit fields, m2 = b411c7f, m3 = f96470c, m4 = 2cc4840,
# m5 = a7ac66b, m6 = fe05443. Paths are this session's build/ layout.
# phase2.sh: stage timings on a quiet machine. Self-check interleaved, then
# blot2 runs one at a time (each ends when the alternatives' region fills).
W=/home/user/goose-to-wasm
cd $W
args=""
for st in base-prog eff4 fn1 rp2 m1 m2 m3 m4 m5 m6; do args="$args $st=$W/build/exp/$st.exe"; done
python3 build/tools/selfcheck.py build/runs/selfcheck-stages.json 5 $args > build/runs/selfcheck-stages.log 2>&1
for st in base-prog eff4 rp2 m2 m3 m6; do
  python3 build/tools/run.py --timeout 1500 --cwd build/blot2-93c8fa8/compiler-goose/src --stderr $W/build/runs/blot2-$st.txt --json $W/build/runs/blot2-stages.jsonl --label $st -- $W/build/exp/$st.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check > build/runs/blot2-$st.out 2>&1
done
echo DONE > build/runs/phase2.done
