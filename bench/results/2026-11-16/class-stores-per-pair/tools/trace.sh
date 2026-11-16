#!/bin/bash
# trace.sh: build build/work with dbgstore2, dbgdefer and the untyped-store tally, run blot2, print the tallies.
W=/home/user/goose-to-wasm; cd $W
rm -rf build/tmp/clso && mkdir -p build/tmp/clso && cp build/work/*.goose build/tmp/clso/ && python3 build/tools/dbgstore2.py build/tmp/clso 1 && python3 build/tools/dbgdefer.py build/tmp/clso && python3 build/tools/dbgwhy.py build/tmp/clso || exit 1
(bash build/tools/mk.sh build/tmp/clso build/exp/clso.exe 2>&1 | grep 'error\|built' | sort -u | head -5); rm -f build/exp/*.exe.c
cd build/blot2-head/compiler-goose/src && python3 $W/build/tools/watch_rss.py 12500 $W/build/runs/clso-blot2.err -- $W/build/exp/clso.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check > $W/build/runs/clso-blot2.out 2>&1
cd $W; grep -a DBGCOUNT build/runs/clso-blot2.err
for k in body map perm argarg; do printf "$k "; grep -a -c "DBGDEFER $k" build/runs/clso-blot2.err; done
grep -a DBGWHY build/runs/clso-blot2.err | cut -d' ' -f2,3 | sort | uniq -c | sort -rn
