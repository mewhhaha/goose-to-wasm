#!/bin/bash
# (As run: the scripts of this folder copied to build/tools/, the repository at /home/user/goose-to-wasm.)
# prove-final.sh BASE_COMMIT: logical-state proof of selfhost/ against BASE_COMMIT's: self-check, corpus, and both
# again with class-keyed frames from frame 64 (corpus, self-check) and 1000 (self-check).
W=/home/user/goose-to-wasm; cd $W; BASE=$1
bash build/tools/fplogical.sh $BASE . final 2>&1 | tail -3
rm -rf build/tmp/fpc-final; python3 build/tools/fpcompare.py build/exp/lfp-base.exe build/exp/lfp-final.exe build/tmp/fpc-final --jobs 4 2>&1 | tail -1
for n in 64 1000; do
  for v in base final; do
    [ $v = base ] && [ -x build/exp/lfp$n-base.exe ] && continue
    rm -rf build/lfpt-$v; mkdir -p build/lfpt-$v
    if [ $v = base ]; then git archive $BASE selfhost | tar -x -C build/lfpt-$v; else cp -r selfhost build/lfpt-$v/selfhost; fi; rm -rf build/lfpt-$v/selfhost/results
    sed -i "s/^let LIFE_CONCRETE_FRAMES: i64 = 4096;/let LIFE_CONCRETE_FRAMES: i64 = $n;/" build/lfpt-$v/selfhost/checker_lifetimes.goose
    python3 build/tools/logicalfp.py build/lfpt-$v/selfhost fingerprint
    G=$W/build/q-s2/bootstrap/bin/goose bash build/tools/mk.sh build/lfpt-$v/selfhost build/exp/lfp$n-$v.exe 2>&1 | grep "error\|built"; rm -f build/exp/lfp$n-$v.exe.c
  done
  for v in base final; do build/exp/lfp$n-$v.exe build/fp-wl/selfhost/main.goose --stdlib stdlib --check > build/tmp/sp/lfp$n-$v.out 2> build/tmp/sp/lfp$n-$v.txt; echo "threshold $n $v rc=$? $(grep -c LIFEFP build/tmp/sp/lfp$n-$v.txt) lines"; done
  cmp build/tmp/sp/lfp$n-base.txt build/tmp/sp/lfp$n-final.txt && cmp build/tmp/sp/lfp$n-base.out build/tmp/sp/lfp$n-final.out && echo "THRESHOLD-$n-SELFCHECK-SAME"
done
rm -rf build/tmp/fpc-final64; python3 build/tools/fpcompare.py build/exp/lfp64-base.exe build/exp/lfp64-final.exe build/tmp/fpc-final64 --jobs 4 2>&1 | tail -1
echo proved
