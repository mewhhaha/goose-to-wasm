The six headers in `runtime/` are unmodified Goose plain-C runtime source.
`runtime/manifest.json` pins the upstream revision and SHA-256 of every
vendored file; `LICENSE` and `NOTICE` accompany them. Builds need no upstream
checkout, C++ compiler or network.

`python3 native/pack.py --section standalone --output /tmp/runtime.c` emits
deterministic C. The Python API `runtime_sections()` returns `header`, `body`,
`glue` and `ffi_header`. Emit `header`, then `body`, then generated packed
`gs_rhdr`, `gs_rref` and `sl_u8` declarations, then `glue`, then program code.
Define options such as `GS_NEED_THREADS` before `header`. Every section retains
system includes and guards; only local includes are removed.

`standalone` supplies the three core types itself. `object` emits a runtime
translation unit with external linkage and all thread support. To link it,
the program emits `header`, generated types and `runtime_ext.h`, with
`GS_SEPARATE_RUNTIME=1` and `GS_NEED_THREADS=1` before `header`; omit `body`
and `runtime_os.h`.
Use identical `GS_RUNTIME_VERSION` when naming a separately linked runtime.
`ffi_header` is the `goose.h` sidecar interface, not a generated-program section.

Run `python3 native/tests/check.py --output /dev/shm/native-runtime-check` for
the upstream lifecycle and trim-memory contracts through direct headers and
amalgamated C, plus an extern-support/OS smoke check. It records commands,
input hashes, toolchain identity, timing and peak RSS in the output directory.

Native lowering embeds `runtime.h`, `runtime_impl.h`, `runtime_threads.h` and
`storage.h`. Grow/GrowShrink arrays use stable indexed regions, caller result
destinations and scope watermarks. Native references are addresses. The old
variable-image adapter, closure allocations and OS adapters remain pending
their image/ABI migration; this is not a fully bounded runtime yet.

`tests/ordinary_regions.goose` checks loop reuse, retained references, result
ownership, recursive forwarding, nonlocal returns and trim/regrowth. Compile
its emitted C with `-DGS_STACK_STATS=1` for region counts, final live bytes,
the sum of each region's high-water bytes and retained legacy bytes.

Large aggregate values use a scoped fixed-value region and address parameters.
`tests/large_values.goose` checks receiving, recursion, nonlocal returns and
loop reuse. The C checks also cover fixed-value watermarks and independent
copies of slot and span freelists under ASan/UBSan.
