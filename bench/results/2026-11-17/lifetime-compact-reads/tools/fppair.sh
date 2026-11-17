#!/bin/bash
# (As run: the scripts of this folder copied to build/tools/, the repository at /home/user/goose-to-wasm.)
# fppair.sh BASE_COMMIT CAND_DIR [WORKLOAD_COMMIT]: build fingerprinting compilers of BASE_COMMIT's selfhost and of
# CAND_DIR/selfhost, run both checking WORKLOAD_COMMIT's selfhost (default BASE_COMMIT's), compare the state lines.
W=/home/user/goose-to-wasm; cd $W; BASE=$1; D=$2; WL=${3:-$1}; T=bench/results/2026-11-14/blot2-lifetimes/tools
mkdir -p build/tmp/sp; rm -rf build/fp-base build/fp-cand build/fp-wl; mkdir -p build/fp-base build/fp-cand build/fp-wl
git archive $BASE selfhost | tar -x -C build/fp-base; git archive $WL selfhost | tar -x -C build/fp-wl; ln -s $W/native build/fp-wl/native; cp -r $D/selfhost build/fp-cand/selfhost
for v in base cand; do
  python3 $T/instrument.py build/fp-$v/selfhost fingerprint >/dev/null
  G=$W/build/q-s2/bootstrap/bin/goose bash build/tools/mk.sh build/fp-$v/selfhost build/exp/fp-$v.exe 2>&1 | grep "error\|built"; rm -f build/exp/fp-$v.exe.c
  build/exp/fp-$v.exe build/fp-wl/selfhost/main.goose --stdlib stdlib --check > build/tmp/sp/fp-$v.out 2> build/tmp/sp/fp-$v.txt; echo "$v rc=$?"
done
cmp build/tmp/sp/fp-base.txt build/tmp/sp/fp-cand.txt && cmp build/tmp/sp/fp-base.out build/tmp/sp/fp-cand.out && echo FINGERPRINTS-SAME $(wc -l < build/tmp/sp/fp-cand.txt) lines
