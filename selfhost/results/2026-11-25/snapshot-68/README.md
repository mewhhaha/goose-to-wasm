# Snapshot 68 · 2026-11-25

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the cross-platform portability batch (`native/storage.h`, `native/slice_pool.h`, `selfhost/codegen_c.goose`, `selfhost/sources.goose`, `selfhost/bootstrap.py`, `scripts/bootstrap.py`, replacing Snapshot 67 `2f1fb59a…`, 2026-11-25).

Changes from Snapshot 67 to Snapshot 68:
- `native/storage.h`: guard POSIX headers/APIs with `#ifndef _WIN32`, implement native stack base inspection on macOS (`pthread_get_stackaddr_np`/`pthread_get_stacksize_np`) and Windows (`VirtualQuery`), add Windows Win32 implementations of `g_os_{write_atomic,kind,time,sleep,random,list}` and `flockfile`/`funlockfile` (`_lock_file`/`_unlock_file`).
- `native/slice_pool.h`: add Windows `VirtualFree`/`VirtualAlloc` discard and `GetSystemInfo` page-size support.
- `selfhost/codegen_c.goose`: add Windows & macOS implementations of `g_os_{path_op,rename,resource}` (`GetModuleFileNameA` / `_NSGetExecutablePath`) and `g_external` (`GetModuleHandleA`/`LoadLibraryA`/`GetProcAddress`, mapping `"libc.so.6"` transparently on macOS & Windows), guard `_GNU_SOURCE` with `#ifndef _WIN32`.
- `selfhost/sources.goose`: preserve Windows drive prefix (`C:`) across `..` normalization.
- `selfhost/bootstrap.py` & `scripts/bootstrap.py`: target-aware link flags (`-lm` on Windows, `-lm -lpthread` on macOS, `-lm -ldl -pthread` on Linux) and `.exe` handling on Windows.
- `.github/workflows/release.yml`: automated multi-platform release workflow building and smoke-testing Linux x64, macOS arm64, macOS x64, Windows x64 (`goosew.exe` using only system DLLs), and portable Wasm64 (`goosew.wasm`).

| Item | Identity |
| --- | --- |
| Seed C | `9256dfdaf2c627475220a6c1b2cd76713fad43f078487d922c6d6db918ecd846` (`25,900,618 B`, stage 2 = stage 3 from Snapshot 67's seed `2f1fb59a…`) |
| Compressed seed | `seed.c.gz` (`4,320,283 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `81519b52735dfd101a7051e4bb467326cb028d2d7668d2f10629a37660c59d47` (`771,608 B`) |
| Executable with profile | `19448064c8878dc779cf993d6498cdd6a7181b654d143f0c55fbc01ce97e6368` |
| Executable without profile | `0017b324be7e545ecab5561a113eee2b86f1ab57b3d0d267cb056be2563cc1a3` |

**Cross-compilation checks.** Verified locally via `zig cc` before freezing: full `goosew.c`, `spans.c`, and `squares.c` compile cleanly for `x86_64-windows-gnu` (imports only `KERNEL32.dll` + Universal CRT `api-ms-win-crt-*`), `aarch64-macos`, and `x86_64-macos`; portable `goosew.wasm` (`--wasm-memory64 -O2`) runs in Wasmtime and compiles `examples/squares.goose` to valid Wasm (`sum=140`).

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`31.5 s`) and with explicit options (`33.9 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `19448064…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-snapshot-68 --jobs 8 --units-pass always` passed all stages in `639.7 s` (cold native cache after `storage.h` edits) using the profiled executable `19448064…` (`bootstrap` `29.9 s`, `profile_used: true`, `10,799/10,801` conformance, `6,022/6,022` split-unit native, `4,773/4,779` memory64, `54/54` native checks, all unit test suites exit 0, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
