#!/bin/bash
# cycle.sh NAME: build build/work class-everywhere (cls0.exe) and with progress
# counters (clsp.exe), run the upstream sentinel tests and the class-everywhere
# self-check, then blot2; results in build/runs/NAME-blot2.{out,err}.
W=/home/user/goose-to-wasm; N=$1; cd $W
build/tools/mkcls.sh 2>&1 | tail -2
cd build/runs/v8-corpus0/upstream
for T in store_class_view_reached class_store_view_outlived store_reached_alias store_class_view_reached_call cycle_read_through_two_pools emptied_callee_call_between emptied_callee_derived_store store_reached_table construct_use_bound_holder_ref shrink_class_copy_kept_own emptied_callee_shrink_first; do printf '%s:%s ' $T $($W/build/exp/cls0.exe test/errors_tc/$T.goose --target native --check --stdlib stdlib 2>&1 | grep -c error); done; echo
cd $W
(build/exp/cls0.exe selfhost/main.goose --stdlib stdlib --target native --check 2>&1 | sed 's/.*error: //' | sort | uniq -c | head -3; echo "self exit ${PIPESTATUS[0]}")
rm -rf build/tmp/clsp && mkdir -p build/tmp/clsp && cp build/work/*.goose build/tmp/clsp/ && python3 build/tools/progress.py build/tmp/clsp && (bash build/tools/mk.sh build/tmp/clsp build/exp/clsp.exe 2>&1 | grep 'error\|built' | sort -u | head -3)
rm -f build/exp/*.exe.c
[ "$2" = noblot ] && exit 0
cd build/blot2-head/compiler-goose/src
python3 $W/build/tools/watch_rss.py 12500 $W/build/runs/$N-blot2.err -- $W/build/exp/clsp.exe main.goose --stdlib $W/stdlib --reachable-program --expansion-node-limit 1000000 --check > $W/build/runs/$N-blot2.out 2>&1
cd $W
tail -c 600 build/runs/$N-blot2.out | tr '\n' ' ' | cut -c1-600; echo
grep -a "frames=" build/runs/$N-blot2.err | tail -1 | cut -c1-300
grep -a "error:" build/runs/$N-blot2.err build/runs/$N-blot2.out | sed 's/.*error: //' | sort | uniq -c | sort -rn | head -5
