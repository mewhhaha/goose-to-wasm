#!/bin/bash
# corpus0.sh NAME: build build/work with the fingerprint instrument twice, at
# the default limit (NAME-fp.exe) and with every eligible call class-keyed
# (NAME-fp0.exe), and compare both against the baseline fingerprint build
# over the corpus: the first must not differ at all, the second is
# categorized by how its diagnostics differ.
set -e
W=/home/user/goose-to-wasm; N=$1; BASE=${BASE:-$W/build/exp/fps-m6.exe}
cd $W
rm -rf build/tmp/$N-fp build/tmp/$N-fp0 && mkdir -p build/tmp/$N-fp build/tmp/$N-fp0
cp build/work/*.goose build/tmp/$N-fp/ && python3 build/tools/instrument.py build/tmp/$N-fp fingerprint >/dev/null
cp build/tmp/$N-fp/*.goose build/tmp/$N-fp0/
sed -i 's/^let LIFE_CONCRETE_FRAMES: i64 = 4096;/let LIFE_CONCRETE_FRAMES: i64 = 0;/' build/tmp/$N-fp0/checker_lifetimes.goose
grep -q 'LIFE_CONCRETE_FRAMES: i64 = 0;' build/tmp/$N-fp0/checker_lifetimes.goose
bash build/tools/mk.sh build/tmp/$N-fp build/exp/$N-fp.exe 2>&1 | grep 'error\|built' | sort -u | head -5
bash build/tools/mk.sh build/tmp/$N-fp0 build/exp/$N-fp0.exe 2>&1 | grep 'error\|built' | sort -u | head -5
rm -rf build/runs/$N-corpus build/runs/$N-corpus0
python3 build/tools/fpcompare.py $BASE $W/build/exp/$N-fp.exe $W/build/runs/$N-corpus --jobs 4 2>&1 | tail -3
python3 build/tools/fpcompare.py $BASE $W/build/exp/$N-fp0.exe $W/build/runs/$N-corpus0 --jobs 4 2>&1 | tail -3
python3 build/tools/diffcat.py $W/build/runs/$N-corpus0 $BASE $W/build/exp/$N-fp0.exe 2>&1 | tail -12
