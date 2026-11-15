#!/bin/bash
# refs.sh NAME TIMEOUT: runs one upstream reference build's `goose check
# main.goose` on the frozen blot2 copy, with its own stdlib.
W=/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a17bf72e44110d4f2
U=/home/jacobt/src/blot2/build/goose-port/upstream-32a4f44
case $1 in
  upstream) B=$U/build-upstream/goose; L=$U/source-upstream/stdlib;;
  patched) B=$U/build-new-patched-v2/goose; L=$U/source-new-patched-v2/stdlib;;
  precision) B=$U/build-new-precision-v2/goose; L=$U/source-new-precision-v2/stdlib;;
esac
mkdir -p $W/build/runs/ref
taskset -c 0-5 python3 $W/build/tools/run.py --timeout $2 --cwd $W/build/blot2/src --stderr $W/build/runs/ref/$1.err \
  --stdout $W/build/runs/ref/$1.out --json $W/build/runs/runs.jsonl --label ref-$1 -- $B check main.goose --stdlib $L
