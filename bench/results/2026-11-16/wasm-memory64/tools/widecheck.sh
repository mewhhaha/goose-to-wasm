#!/bin/bash
# widecheck.sh [sources...]: with build/exp/gw.exe, compile each source for wasm-direct twice (32-bit and
# --wasm-memory64), type-check the 64-bit module with wasmcheck.py, run both under the Node host and
# compare what they print. Default sources: examples/*.goose. NOBUILD=1 skips nothing (it never builds).
W=/home/user/goose-to-wasm; cd $W
C=${C:-$W/build/exp/gw.exe}; T=build/tmp/wc; mkdir -p $T
[ $# -gt 0 ] || set -- examples/*.goose
ok=0; bad=0
for src in "$@"; do
  n=$(basename $src .goose)
  $C $src --stdlib stdlib --target wasm-direct ${OPT:--O2} --debug -o $T/$n.n.wasm >$T/$n.n.err 2>&1; rn=$?
  $C $src --stdlib stdlib --target wasm-direct ${OPT:--O2} --debug --wasm-memory64 ${WIDE_ARGS:-} -o $T/$n.w.wasm >$T/$n.w.err 2>&1; rw=$?
  if [ $rn != 0 ]; then continue; fi
  if [ $rw != 0 ]; then bad=$((bad+1)); echo "COMPILE $src: $(head -c 200 $T/$n.w.err)"; continue; fi
  v=$(python3 build/tools/wasmcheck.py $T/$n.w.wasm --max ${MAXERR:-3} 2>&1)
  if ! echo "$v" | tail -1 | grep -q ", 0 with errors"; then bad=$((bad+1)); echo "INVALID $src: $(echo "$v" | tail -1)"; echo "$v" | head -${SHOW:-12}; continue; fi
  timeout 60 node scripts/run_wasm.mjs $T/$n.n.wasm </dev/null >$T/$n.n.out 2>$T/$n.n.eo; en=$?
  timeout 60 node scripts/run_wasm.mjs $T/$n.w.wasm </dev/null >$T/$n.w.out 2>$T/$n.w.eo; ew=$?
  if [ $en = $ew ] && cmp -s $T/$n.n.out $T/$n.w.out && cmp -s $T/$n.n.eo $T/$n.w.eo; then ok=$((ok+1)); rm -f $T/$n.*; else bad=$((bad+1)); echo "RUN $src ($en vs $ew): $(head -c 300 $T/$n.w.eo)"; fi
done
echo "wide: same $ok different $bad"
