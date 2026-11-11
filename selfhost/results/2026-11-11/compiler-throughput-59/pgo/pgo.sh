#!/bin/bash
# pgo.sh NAME SEEDC : build plain + PGO binaries with the snapshot-58 training protocol
set -e
NAME=$1; SEED=$2; R=/home/jacobt/src/goose-to-wasm; W=$R/build/completion-runs/compiler-subtractive-58
D=/var/tmp/goose-perf/pgo/$NAME; rm -rf $D; mkdir -p $D; cd $D
cp $SEED seed.c; cp -r $R/selfhost sources; rm -rf sources/results sources/__pycache__; cp -r $R/stdlib stdlib; cp -r $R/native native
printf '#include <stdlib.h>\nint __llvm_profile_write_file(void);\n_Noreturn void __real__Exit(int);\n_Noreturn void __wrap__Exit(int code){__llvm_profile_write_file();__real__Exit(code);}\n' > profile-exit.c
BASE="-std=gnu11 -O2 seed.c -lm -ldl -pthread"
clang-23 $BASE -o goose-plain 2>/dev/null &
clang-23 $BASE -fprofile-instr-generate profile-exit.c -Wl,--wrap=_Exit -o goose-train 2>/dev/null &
wait
./goose-plain ./sources/main.goose --stdlib stdlib --target native -O2 -o verify.c
cmp verify.c seed.c && echo "fixed point ok" || echo "NOT FIXED POINT"
LLVM_PROFILE_FILE=$D/native-%p.profraw ./goose-train ./sources/main.goose --stdlib stdlib --target native -O2 -o training-native.out
LLVM_PROFILE_FILE=$D/leaf-%p.profraw ./goose-train $W/leaf-properties-fixture.goose --stdlib stdlib --target wasm-direct -O2 -o training-leaf.out
LLVM_PROFILE_FILE=$D/flow-%p.profraw ./goose-train $W/flow-prefilter-fixture.goose --stdlib stdlib --target wasm-direct -O2 -o training-flow.out
llvm-profdata merge -o profile.profdata -weighted-input=1,$(ls native-*.profraw) -weighted-input=64,$(ls leaf-*.profraw) -weighted-input=64,$(ls flow-*.profraw)
clang-23 $BASE -fprofile-instr-use=profile.profdata -Werror=profile-instr-out-of-date -Werror=profile-instr-unprofiled -Werror=profile-instr-missing -o goose-pgo 2>pgo-build.stderr
./goose-pgo ./sources/main.goose --stdlib stdlib --target native -O2 -o verify-pgo.c
cmp verify-pgo.c seed.c && echo "pgo fixed point ok"
sha256sum seed.c goose-plain goose-pgo profile.profdata
