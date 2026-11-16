#!/bin/bash
# narrowcheck.sh: build selfhost as build/exp/gw.exe and compare its wasm32 output with the baseline
# compiler's on the examples, the compiler itself and a sample of conformance sources (byte for byte).
W=/home/user/goose-to-wasm; cd $W
B=${BASE:-$W/build/q-wasm1/bootstrap/bin/goose}
(bash build/tools/mk.sh selfhost build/exp/gw.exe ${CFLAGS_EXTRA:-} 2>&1 | grep 'error\|built' | sort -u | head -8); rm -f build/exp/*.exe.c
mkdir -p build/tmp/nc; same=0; diff=0
check() {
  src=$1; shift
  $B $src --stdlib stdlib --target wasm-direct "$@" -o build/tmp/nc/b.wasm >build/tmp/nc/b.out 2>&1; rb=$?
  build/exp/gw.exe $src --stdlib stdlib --target wasm-direct "$@" -o build/tmp/nc/c.wasm >build/tmp/nc/c.out 2>&1; rc=$?
  if [ $rb = $rc ] && cmp -s build/tmp/nc/b.out build/tmp/nc/c.out && { [ $rb != 0 ] || cmp -s build/tmp/nc/b.wasm build/tmp/nc/c.wasm; }; then same=$((same+1)); else diff=$((diff+1)); echo "DIFF $src $* ($rb vs $rc) $(head -c 160 build/tmp/nc/c.out)"; fi
  rm -f build/tmp/nc/b.wasm build/tmp/nc/c.wasm
}
for f in examples/*.goose; do check $f -O2; check $f -O0; done
check selfhost/main.goose -O2 --wasm-max-pages 65535
for f in $(ls tests/fixtures/*.goose | head -${NC_FIXTURES:-150}); do check $f -O2; done
echo "narrow: same $same different $diff"
