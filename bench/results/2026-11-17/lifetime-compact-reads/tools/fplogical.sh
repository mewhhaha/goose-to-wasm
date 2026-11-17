#!/bin/bash
# (As run: the scripts of this folder copied to build/tools/, the repository at /home/user/goose-to-wasm.)
# fplogical.sh BASE_COMMIT CAND_DIR NAME: build logical-fingerprint compilers of BASE_COMMIT's selfhost and of
# CAND_DIR/selfhost (build/exp/lfp-base.exe, build/exp/lfp-NAME.exe) and compare their state lines on BASE_COMMIT's selfhost.
W=/home/user/goose-to-wasm; cd $W; BASE=$1; D=$2; N=$3
mkdir -p build/tmp/sp; rm -rf build/lfp-base build/lfp-$N build/fp-wl; mkdir -p build/lfp-base build/lfp-$N build/fp-wl
git archive $BASE selfhost | tar -x -C build/lfp-base; rm -rf build/lfp-base/selfhost/results
git archive $BASE selfhost | tar -x -C build/fp-wl; rm -rf build/fp-wl/selfhost/results; ln -s $W/native build/fp-wl/native
cp -r $D/selfhost build/lfp-$N/selfhost; rm -rf build/lfp-$N/selfhost/results
for v in base $N; do
  [ $v = base ] && [ -x build/exp/lfp-base.exe ] && [ "$(cat build/exp/lfp-base.commit 2>/dev/null)" = "$(git rev-parse $BASE)" ] || {
    python3 build/tools/logicalfp.py build/lfp-$v/selfhost fingerprint
    G=$W/build/q-s2/bootstrap/bin/goose bash build/tools/mk.sh build/lfp-$v/selfhost build/exp/lfp-$v.exe 2>&1 | grep "error\|built"; rm -f build/exp/lfp-$v.exe.c
    [ $v = base ] && git rev-parse $BASE > build/exp/lfp-base.commit
  }
  build/exp/lfp-$v.exe build/fp-wl/selfhost/main.goose --stdlib stdlib --check > build/tmp/sp/lfp-$v.out 2> build/tmp/sp/lfp-$v.txt; echo "$v rc=$? $(grep -c LIFEFP build/tmp/sp/lfp-$v.txt) lines"
done
cmp build/tmp/sp/lfp-base.txt build/tmp/sp/lfp-$N.txt && cmp build/tmp/sp/lfp-base.out build/tmp/sp/lfp-$N.out && echo LOGICAL-STATE-SAME
