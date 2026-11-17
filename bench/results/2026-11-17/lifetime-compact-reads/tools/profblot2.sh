#!/bin/bash
# profblot2.sh NAME SELFHOST_DIR: build SELFHOST_DIR with frame pointers, sample its check of the blot2 copy, print the top.
W=/home/user/goose-to-wasm; cd $W; N=$1; B=$W/build/blot2-head/compiler-goose/src; T=bench/results/2026-11-15/lifetime-walks-and-memos/tools
G=$W/build/q-s2/bootstrap/bin/goose bash build/tools/mk.sh $2 build/exp/pb-$N.exe -fno-omit-frame-pointer -g 2>&1 | grep "error\|built"
( cd $B && PROF_OUT=$W/build/tmp/sp/pb-$N.out LD_PRELOAD=$W/build/tools/prof.so $W/build/exp/pb-$N.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check > /dev/null 2>&1 )
python3 $T/report.py build/exp/pb-$N.exe build/tmp/sp/pb-$N.out 40 > build/tmp/sp/pb-$N.txt 2>&1; head -3 build/tmp/sp/pb-$N.txt
