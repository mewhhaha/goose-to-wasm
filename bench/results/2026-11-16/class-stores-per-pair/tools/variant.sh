#!/bin/bash
# variant.sh NAME 'python edit of t (the source text)': build build/work with
# every eligible call class-keyed and one edit applied, as build/exp/NAME.exe.
set -e
W=/home/user/goose-to-wasm; N=$1
cd $W; rm -rf build/tmp/$N && mkdir -p build/tmp/$N && cp build/work/*.goose build/tmp/$N/
sed -i 's/^let LIFE_CONCRETE_FRAMES: i64 = 4096;/let LIFE_CONCRETE_FRAMES: i64 = 0;/' build/tmp/$N/checker_lifetimes.goose
python3 - "$N" "$2" <<'PY'
import sys
f='/home/user/goose-to-wasm/build/tmp/%s/checker_lifetimes.goose'%sys.argv[1]
t=open(f).read()
exec(sys.argv[2])
open(f,'w').write(t)
PY
bash build/tools/mk.sh build/tmp/$N build/exp/$N.exe 2>&1 | grep 'error\|built' | sort -u | head -5
