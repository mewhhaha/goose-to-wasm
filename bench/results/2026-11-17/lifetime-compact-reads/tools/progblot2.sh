#!/bin/bash
# progblot2.sh BASE_COMMIT CAND_DIR: instrument.py progress builds of both, each run on the blot2 copy: a line with
# milliseconds and table sizes every 1,000 frames (build/tmp/sp/prog-base.txt, prog-cand.txt).
W=/home/user/goose-to-wasm; cd $W; B=$W/build/blot2-head/compiler-goose/src; T=bench/results/2026-11-14/blot2-lifetimes/tools
rm -rf build/prog-base build/prog-cand; mkdir -p build/prog-base build/prog-cand
git archive $1 selfhost | tar -x -C build/prog-base; cp -r $2/selfhost build/prog-cand/selfhost; rm -rf build/prog-base/selfhost/results build/prog-cand/selfhost/results
for v in base cand; do
  python3 build/tools/progress.py build/prog-$v/selfhost
  G=$W/build/q-s2/bootstrap/bin/goose bash build/tools/mk.sh build/prog-$v/selfhost build/exp/prog-$v.exe 2>&1 | grep "error\|built"; rm -f build/exp/prog-$v.exe.c
done
for v in cand base; do ( cd $B && $W/build/exp/prog-$v.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check > /dev/null > $W/build/tmp/sp/prog-$v.err 2>&1 ); grep LIFEPROG build/tmp/sp/prog-$v.err > build/tmp/sp/prog-$v.txt; wc -l < build/tmp/sp/prog-$v.txt; done
echo done
