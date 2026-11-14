#!/bin/sh
real=/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a636162323a6482dc/build/q-abandon/bootstrap/bin/goose
for a do shift; [ "$a" = --offline ] || set -- "$@" "$a"; done
exec "$real" "$@"
