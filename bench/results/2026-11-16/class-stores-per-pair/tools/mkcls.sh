#!/bin/bash
# mkcls.sh: build build/work as cls.exe (default limit), cls0.exe (every
# eligible call class-keyed) and cls0d.exe (the latter with debug prints).
set -e
W=/home/user/goose-to-wasm
cd $W
rm -rf build/tmp/cls0 build/tmp/cls0d && mkdir -p build/tmp/cls0 build/tmp/cls0d
cp build/work/*.goose build/tmp/cls0/
sed -i 's/^let LIFE_CONCRETE_FRAMES: i64 = 4096;/let LIFE_CONCRETE_FRAMES: i64 = 0;/' build/tmp/cls0/checker_lifetimes.goose
grep -q 'LIFE_CONCRETE_FRAMES: i64 = 0;' build/tmp/cls0/checker_lifetimes.goose
cp build/tmp/cls0/*.goose build/tmp/cls0d/
python3 build/tools/dbgshrink.py build/tmp/cls0d
bash build/tools/mk.sh build/tmp/cls0 build/exp/cls0.exe 2>&1 | grep 'error\|built' | sort | uniq | head -20
if [ "$1" = all ]; then
  bash build/tools/mk.sh build/work build/exp/cls.exe 2>&1 | grep 'error\|built' | sort | uniq | head
  bash build/tools/mk.sh build/tmp/cls0d build/exp/cls0d.exe 2>&1 | grep 'error\|built' | sort | uniq | head
fi
