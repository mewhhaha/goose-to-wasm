#!/bin/bash
# fpself.sh WORKDIR: build a fingerprinting copy of WORKDIR/selfhost and compare its self-check state lines
# with the baseline's (build/tmp/sp/fp-base.txt, from selfhost/ at the start of this work).
W=/home/user/goose-to-wasm; cd $W; D=$1; T=bench/results/2026-11-14/blot2-lifetimes/tools
rm -rf build/fp-cand && mkdir -p build/fp-cand && cp -r $D/selfhost build/fp-cand/selfhost && python3 $T/instrument.py build/fp-cand/selfhost fingerprint >/dev/null
G=$W/build/q-r2/bootstrap/bin/goose bash build/tools/mk.sh build/fp-cand/selfhost build/exp/fp-cand.exe 2>&1 | grep "error\|built"; rm -f build/exp/fp-cand.exe.c
build/exp/fp-cand.exe selfhost/main.goose --stdlib stdlib --check 2> build/tmp/sp/fp-cand.txt; echo rc=$?
cmp build/tmp/sp/fp-base.txt build/tmp/sp/fp-cand.txt && echo FINGERPRINTS-SAME $(wc -l < build/tmp/sp/fp-cand.txt) lines
