#!/bin/bash
# mk.sh SELFHOST_DIR OUT_EXE [extra cflags...]
# Emits the compiler's C with a built compiler ($G, default the 9806 dev
# build) and compiles it as 8 units with clang -O2 plus extra flags.
set -e
W=/home/user/goose-to-wasm
SRC=$(realpath "$1"); OUT=$(realpath -m "$2"); shift 2
G=${G:-$W/build/dev-base/bin/goose}
mkdir -p $W/build/tmp
ST=$(mktemp -d $W/build/tmp/mk.XXXXXX)
mkdir -p $ST/sources && cp $SRC/*.goose $ST/sources/
ln -s $W/native $ST/native
cd $ST
$G sources/main.goose --stdlib $W/stdlib --target native -O2 -o seed.c
python3 -c "
t=open('seed.c').read(); e=t.find('\n#else /* program units */\n'); open('runtime.c','w').write(t[:e+1]+'#endif\n')"
CF="-std=gnu11 -O2 $*"
clang $CF -DG_RUNTIME_UNIT -c runtime.c -o runtime.o &
for u in 0 1 2 3; do clang $CF -DG_UNITS=8 -DG_UNIT=$u -c seed.c -o unit$u.o & done; wait; for u in 4 5 6 7; do clang $CF -DG_UNITS=8 -DG_UNIT=$u -c seed.c -o unit$u.o & done
wait
clang $CF runtime.o unit*.o -lm -ldl -pthread -o "$OUT"
cp seed.c "$OUT.c"
cd $W
rm -rf $ST
echo built $OUT
