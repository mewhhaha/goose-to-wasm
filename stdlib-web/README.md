# Web standard library

Use `--stdlib stdlib-web` in place of `--stdlib stdlib` when compiling a
Goose program that uses `slice_pool` for Direct Wasm.

```sh
build/bin/goosew program.goose --target wasm-direct --stdlib stdlib-web -o program.wasm
```

The core modules are copied from the pinned standard library. The slice pool
uses a Goose port of the native B+ span tree with the same API and node layout.
Its `trim()` zeroes the complete 4096-byte pages inside free spans, aligned
relative to the backing byte array. Those pages stay in the backing allocation.
For pools that exceed the default Wasm region budget, raise `--wasm-max-pages`.

`stdlib-web` also provides browser-ready drop-in modules for `audio`, `gfx`,
`ui`, and `physics` backed by `host/web/` (Web Audio, WebGL2 + JSPI, Canvas 2D
UI overlay, and pure-JS 3D rigid-body physics).

Switch back with `--stdlib stdlib` to use the pinned library and its native
slice pool runtime.
