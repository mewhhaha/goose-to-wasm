#!/bin/bash
# v8.sh COMPILER WORKDIR: the compiler as a Wasm module under V8 (node scripts/run_wasm.mjs) on its own source.
# A 64-bit module for 16 GiB with equal regions (no profile): check three times, compile itself once and compare
# with its own bytes. A 32-bit module with equal regions: check. A 32-bit module with a region profile taken from
# a Wasmtime self-compile (host/rust): check three times, compile itself once and compare. Wall seconds.
G=$1; W=$2; mkdir -p $W; S="selfhost/main.goose --stdlib stdlib"; H=host/rust/target/release/goose-wasmtime
t() { local s=$(date +%s.%N); "$@" < /dev/null > $W/out.txt 2>&1; local rc=$?; echo "$(echo "$(date +%s.%N) - $s" | bc | cut -c1-6) s, exit $rc$( [ $rc != 0 ] && echo ": $(tail -1 $W/out.txt)")"; }
node --version; node -p process.versions.v8
$G $S --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144 -o $W/g64.wasm; echo "64-bit module, equal regions: $(stat -c %s $W/g64.wasm) bytes"
for i in 1 2 3; do echo "  check: $(t node scripts/run_wasm.mjs $W/g64.wasm -- $S --check)"; done
echo "  compile itself: $(t node scripts/run_wasm.mjs $W/g64.wasm -- $S --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144 -o $W/self64.wasm)"; cmp $W/self64.wasm $W/g64.wasm && echo "  writes its own bytes"
$G $S --target wasm-direct -O2 --wasm-max-pages 65535 -o $W/g32.wasm; echo "32-bit module, equal regions: $(stat -c %s $W/g32.wasm) bytes"
echo "  check: $(t node scripts/run_wasm.mjs $W/g32.wasm -- $S --check)"
$G $S --target wasm-direct -O2 --wasm-memory64 --wasm-region-stats --wasm-max-pages 4194304 -o $W/stats.wasm
GOOSE_REGION_PROFILE=$W/goose.profile $H $W/stats.wasm --cache $W/stats.cwasm -- $S --target wasm-direct -O2 --wasm-max-pages 65535 -o $W/x.wasm < /dev/null > /dev/null 2>&1
echo "profile: $(wc -l < $W/goose.profile) regions, $(awk '{s+=$2} END {printf "%.0f", s/1000000}' $W/goose.profile) MB of peaks, largest $(sort -k2 -n -r $W/goose.profile | head -3 | awk '{printf "%.1f ", $2/1000000}')MB"
$G $S --target wasm-direct -O2 --wasm-max-pages 65535 --wasm-region-profile $W/goose.profile -o $W/g32p.wasm; echo "32-bit module, regions by that profile: $(stat -c %s $W/g32p.wasm) bytes"
for i in 1 2 3; do echo "  check: $(t node scripts/run_wasm.mjs $W/g32p.wasm -- $S --check)"; done
echo "  compile itself: $(t node scripts/run_wasm.mjs $W/g32p.wasm -- $S --target wasm-direct -O2 --wasm-max-pages 65535 --wasm-region-profile $W/goose.profile -o $W/self32.wasm)"; cmp $W/self32.wasm $W/g32p.wasm && echo "  writes its own bytes"
