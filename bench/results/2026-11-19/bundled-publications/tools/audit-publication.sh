#!/bin/sh
# Run from a checkout with the locked Rust host already built in release mode.
# Supply the baseline and candidate Wasm modules compiled from identical sources.
set -eu
if [ "$#" -ne 2 ]; then
    printf '%s\n' 'usage: audit-publication.sh BEFORE.wasm AFTER.wasm' >&2
    exit 2
fi
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
deps=${GOOSE_AUDIT_DEPS:-"$root/host/rust/target/release/deps"}
compiler=${GOOSE_AUDIT_RUST_TOOLCHAIN:-1.97.1}

library() {
    set -- "$deps/lib$1-"*.rlib
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        printf 'Expected one matching locked Rust host library under %s\n' "$deps" >&2
        return 1
    fi
    printf '%s\n' "$1"
}

wasmparser=$(library wasmparser)
sha2=$(library sha2)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
rustc "+$compiler" --edition=2021 -O -L "dependency=$deps" \
    --extern "wasmparser=$wasmparser" --extern "sha2=$sha2" \
    "$here/audit-publication.rs" -o "$scratch/audit-publication"
"$scratch/audit-publication" "$@"
