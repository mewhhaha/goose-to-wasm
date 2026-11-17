#!/bin/bash
# (As run: the scripts of this folder copied to build/tools/, the repository at /home/user/goose-to-wasm.)
# fpblot2-logical.sh BASE_COMMIT CAND_DIR: logical state lines (logicalfp.py fpframes: every 2,000 frames and at pass
# boundaries) of BASE_COMMIT's selfhost and of CAND_DIR/selfhost on the blot2 copy, one run at a time, compared.
W=/home/user/goose-to-wasm; cd $W; B=$W/build/blot2-head/compiler-goose/src
rm -rf build/fpb-base build/fpb-cand; mkdir -p build/fpb-base build/fpb-cand
git archive $1 selfhost | tar -x -C build/fpb-base; cp -r $2/selfhost build/fpb-cand/selfhost; rm -rf build/fpb-base/selfhost/results build/fpb-cand/selfhost/results
for v in base cand; do
  python3 build/tools/logicalfp.py build/fpb-$v/selfhost fpframes
  G=$W/build/q-s2/bootstrap/bin/goose bash build/tools/mk.sh build/fpb-$v/selfhost build/exp/fpb-$v.exe 2>&1 | grep "error\|built"; rm -f build/exp/fpb-$v.exe.c
done
for v in base cand; do
  ( cd $B && /usr/bin/env bash -c "time $W/build/exp/fpb-$v.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check" > $W/build/tmp/sp/fpb-$v.out 2> $W/build/tmp/sp/fpb-$v.err; echo "$v rc=$?" )
  grep -c LIFEFP build/tmp/sp/fpb-$v.err; grep real build/tmp/sp/fpb-$v.err
  grep LIFEFP build/tmp/sp/fpb-$v.err > build/tmp/sp/fpb-$v.fp; grep -v "LIFEFP\|^real\|^user\|^sys\|^$" build/tmp/sp/fpb-$v.err > build/tmp/sp/fpb-$v.diag
done
cmp build/tmp/sp/fpb-base.fp build/tmp/sp/fpb-cand.fp && echo BLOT2-LOGICAL-STATE-SAME $(wc -l < build/tmp/sp/fpb-cand.fp) lines
cmp build/tmp/sp/fpb-base.diag build/tmp/sp/fpb-cand.diag && cmp build/tmp/sp/fpb-base.out build/tmp/sp/fpb-cand.out && echo BLOT2-OUTPUT-SAME $(wc -l < build/tmp/sp/fpb-cand.diag) diagnostic lines
