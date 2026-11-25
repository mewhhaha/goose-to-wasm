# Snapshot 69 · 2026-11-25

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the audit bug-fix & host-parity batch (`selfhost/optimizer.goose`, `selfhost/checker.goose`, `selfhost/codegen.goose`, `selfhost/codegen_c.goose`, `selfhost/driver.goose`, `native/storage.h`, `scripts/run_wasmtime.py`, `scripts/run_wasm.mjs`, `host/rust`, `host/wtime`, replacing Snapshot 68 `9256dfda…`, 2026-11-25).

Changes from Snapshot 68 to Snapshot 69:
- `selfhost/optimizer.goose` & `selfhost/codegen_c.goose`: fix `u64` `for`-range empty-range folding (compare bounds unsigned when either side is unsigned) and native C `u64` range/count loop lowering (`TYPE_U64` instead of `TYPE_I64`), and wrap folded narrow signed `MIN / -1` (`i8`/`i16`/`i32`) while preserving `--debug` overflow traps.
- `selfhost/checker.goose`, `selfhost/codegen_c.goose`, `selfhost/codegen.goose`: exclude trailing blocks (`N_FUNCTION_VALUE`) from required positional argument matching in `check_choose_call` (matching upstream rejection instead of crashing at `-O2`) and add defensive negative-symbol guards in C and Wasm codegen.
- `selfhost/driver.goose`: fix Windows command quoting, `cmd.exe` exit-code handling, default `CC` (`clang` on Windows), macOS/Windows link flags (`-lm` / `-lm -lpthread`), `--shared` temp cleanup via `delete_file`, default Direct Wasm `--run` host fallback (`GOOSE_WASM_HOST` → `goose-wasmtime` → `node scripts/run_wasm.mjs`), warning/note diagnostic severity labels, and `--expansion-node-limit` error text.
- `native/storage.h` & `selfhost/codegen_c.goose`: upgrade Windows `#ifdef _WIN32` OS shims (`read_file`, `write_file`, `write_file_atomic`, `file_exists`/`is_dir`, `delete_file`/`delete_dir`/`make_dir`, `rename_file`, `list_dir`, `arg`, `env`, `resource_dir`) from ANSI `*A` APIs to UTF-16 `_wfopen`/`*W` APIs, and set Windows `stdin` to `_O_BINARY` in `read_line`/`read_stdin`.
- `scripts/run_wasmtime.py`, `scripts/run_wasm.mjs`, `host/rust`, `host/wtime`: wire all 10 remaining `stdlib/os.goose` imports (`write_file_atomic`, `delete_file`, `rename_file`, `make_dir`, `delete_dir`, `list_dir`, `read_line`, `read_stdin`, `sleep_ms`, `random_seed`) and `gs_os_resource_dir` across all four Direct Wasm hosts, guard `gs_find_pair` against negative/out-of-range distance, fix `run_wasmtime.py` Windows `os.environb` and `threading.stack_size`, and fix `host/wtime` wasm32 `gs_os_arg` pointer-width detection, duplicate import deduplication, and Goose float formatting (`float.rs`).
- `docs/FEATURES.md`: mark decided-comparison warnings as `partial`.

| Item | Identity |
| --- | --- |
| Seed C | `4af0d23ef96891b294662b80f90b1c1a6f3f8d1db90f53a39ff51e23ee7947b8` (`25,949,864 B`, stage 2 = stage 3 from Snapshot 68's seed `9256dfda…`) |
| Compressed seed | `seed.c.gz` (`4,328,007 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `2ad4bebdceb18c494f8825ed68da67b17ef492ce56918983df7911ef84277a65` (`772,656 B`) |
| Executable with profile | `2a0226e5db2511787f7aa7a30cf931df15b55ebe8986607028f74b13dd23d6e1` |
| Executable without profile | `03a5d3c7a89e01c5794ecd9a1310ad28e9647740c910ecfd143d8e681041d4ae` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Cross-compilation checks.** Verified locally via `zig cc`: generated `goosew.c` with the new Win32 UTF-16 shims compiles and links cleanly for `x86_64-windows-gnu` (imports only `KERNEL32.dll` + Universal CRT `api-ms-win-crt-*`), `aarch64-macos`, and `x86_64-macos`.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`33.3 s`) and with explicit options (`37.4 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `2a0226e5…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-snapshot-69 --jobs 8 --units-pass always` passed all stages in `587.6 s` using the profiled executable `2a0226e5…` (`bootstrap` `35.0 s`, `profile_used: true`, `10,799/10,801` conformance, `6,022/6,022` split-unit native, `4,773/4,779` memory64, `54/54` native checks, all 21 unit test suites exit 0, `tests.test_wtime_host` 4/4 OK, `host/rust/tests/compare_hosts.py` 20/20 modules 0 differences, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
