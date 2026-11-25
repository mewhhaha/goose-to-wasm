# Goose in Goose

The compiler is written in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The `goosew` compiler and standard library are installed in `build/bin`. `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Goose emission defaults to `-O2` and the C build uses `-std=gnu11 -O2 -lm -ldl -pthread`.

An optional Clang IR profile is used only when its C hash, target triple, Clang major version, C basename and base flags match, and its data checksum is valid. If the profile is missing, mismatched or fails to compile, bootstrap builds without it and records the reason. The supplied profile targets Clang 23 and `x86_64-pc-linux-gnu`; it was trained on non-timed compiler workloads and contract fixtures, excluding the timed benchmark programs.

Snapshot 69 supplies the checked-in seed and profile (`v2026.4-1`, `goosew` binary, audit fixes, Win32 UTF-16 runtime & full Direct Wasm host parity). Its two independent bootstrap builds verified and produced the same compiler. [Snapshot 69 evidence](results/2026-11-25/snapshot-69/README.md)

## Development

```sh
python3 scripts/bootstrap.py --build-dir build/dev --jobs 8 \
  --cache-dir build/qualify-cache/bootstrap
```

The development build compiles eight program units beside one runtime unit without the profile. The one unit default is the release build. The cache reuses seed C when the seed, options and staged input bytes match. With `--verify`, the resulting compiler generates fresh C for the fixed-point check on every run. Use `--source-dir` to build a separate copy of the compiler sources. Use the [snapshot 69 protocol](results/2026-11-25/snapshot-69/README.md) to freeze a seed and profile.

For local edits, `python3 scripts/bootstrap.py --reuse-toolchain build/toolchain.json` starts with the previously verified local compiler. It checks that executable against its receipt and verifies the new C fixed point before installation. [Measurements](../bench/results/2026-11-17/local-bootstrap/README.md)

Modules found through `--stdlib` are libraries: their function bodies are lexed, parsed and checked only when the program reaches them. Unused functions in user sources are still checked.

See [qualification](../tests/README.md#qualifying-a-change) for the frozen contracts and output comparison. [Open compatibility work](../docs/FEATURES.md#blot2-compatibility) · [Direct target and hosts](../docs/TARGET.md)
