#!/bin/bash
# watch.sh PLACE VALUE: run blot2 with build/exp/clsw.exe watching stores of root VALUE into root PLACE.
W=/home/user/goose-to-wasm; cd $W/build/blot2-head/compiler-goose/src
DBG_WATCH=$1,$2 python3 $W/build/tools/watch_rss.py 12500 $W/build/runs/clsw-blot2.err -- $W/build/exp/clsw.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check > $W/build/runs/clsw-blot2.out 2>&1
cd $W; grep -a DBGWATCH build/runs/clsw-blot2.err | cut -c1-${3:-1200}
