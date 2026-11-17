#!/bin/bash
# stepbench.sh: build the cumulative steps of lifememo.py (and the holder list) from the baseline sources in
# build/fpb-base/selfhost-plain, then time them all with selfbench.py.
W=/home/user/goose-to-wasm; cd $W; rm -rf build/steps; mkdir -p build/steps
git archive ${BASE:-HEAD~1} selfhost | tar -x -C build/steps; mv build/steps/selfhost build/steps/s0
for s in 1 2 3 4 5 6 7; do
  cp -r build/steps/s0 build/steps/s$s
  if [ $s = 7 ]; then python3 build/tools/lifememo.py build/steps/s7/checker_lifetimes.goose 6 >/dev/null; python3 build/tools/holderrefs.py build/steps/s7/checker_lifetimes.goose >/dev/null
  else python3 build/tools/lifememo.py build/steps/s$s/checker_lifetimes.goose $s >/dev/null; fi
done
for s in 0 1 2 3 4 5 6 7; do mkdir -p build/steps/w$s; rm -rf build/steps/w$s/selfhost; mv build/steps/s$s build/steps/w$s/selfhost
  G=$W/build/q-r2/bootstrap/bin/goose bash build/tools/mk.sh build/steps/w$s/selfhost build/exp/step$s.exe 2>&1 | grep "error\|built"; rm -f build/exp/step$s.exe.c; done
cmp build/steps/w7/selfhost/checker_lifetimes.goose selfhost/checker_lifetimes.goose && echo step7-is-final
python3 build/tools/selfbench.py -n 7 build/exp/step0.exe build/exp/step1.exe build/exp/step2.exe build/exp/step3.exe build/exp/step4.exe build/exp/step5.exe build/exp/step6.exe build/exp/step7.exe
