# Goose Web host

Compile a program from the repository root, then serve the Wasm file and this
directory from the same HTTP origin.

```sh
goosew app.goose --stdlib stdlib-web --target wasm-direct -O2 -o app.wasm
```

Add `--wasm-memory64` to target an engine with memory64 support. The loader
detects the address width from Wasm bytes. Supply `{ memory64: true }` when
passing a precompiled memory64 `WebAssembly.Module`. When the width is explicit
and the response is served as `application/wasm`, the loader can instantiate
directly from the response stream. Set `streaming: false` to read the bytes first.

## Run in a browser

```html
<pre id="output"></pre>
<script type="module">
  import { runGoose } from "./host/web/index.js";

  const output = document.querySelector("#output");
  const result = await runGoose("./app.wasm", {
    args: ["app.wasm"],
    files: { "/input.txt": "Hello from the browser\n" },
    onStdout: (_bytes, text) => output.append(text),
    onStderr: (_bytes, text) => console.error(text),
  });

  console.log(result.exitCode, result.fs.snapshot());
</script>
```

`runGoose` runs `_start` by default. It returns the exit status, abort details,
output text and bytes, and the filesystem. Pass `entry` and `entryArgs` for a
different export. Goose exit and abort become result fields unless
`throwOnError` is set. Wasm traps and load failures reject.

Use `loadGoose(source, options)` to keep the instance and call
`loaded.run(entry, ...args)` repeatedly. Captured streams accumulate until
`loaded.host.resetOutput()`. Pass `captureOutput: false` for live callbacks
without capture. Supply `stdin` as text, bytes, or a synchronous chunk
callback. Call `await loaded.dispose()` when finished. For live Web Audio,
create or resume an `AudioContext` in a user gesture, pass it as
`audioContext`, and retain the instance while it plays. The caller closes an
externally provided context.

For TypeScript, include the DOM library for browser types such as
`AudioContext` and `FileSystemDirectoryHandle`.

## Filesystems and workers

- `new MemoryFS({ files, dirs, cwd })` is the default in-memory filesystem.
  Pass an instance as `fs` to share files across runs.
- `new LocalStorageFS({ prefix: "my-app:" })` persists a virtual filesystem in
  browser local storage. Use a separate prefix per application.
- `await OPFSAdapter.open({ name: "my-app-files" })` uses Origin Private File
  System storage with synchronous file handles. Open it inside a dedicated
  worker on a secure origin, pass it to `loadGoose` or `runGoose`, and call
  `fs.close()` to release its handles.

```js
import { createGooseWorker } from "./host/web/index.js";

const worker = createGooseWorker();
try {
  const result = await worker.run("./app.wasm", {
    onStdout: (_bytes, text) => console.log(text),
  });
  console.log(result.exitCode, result.files);
} finally {
  worker.terminate();
}
```

`createGooseWorker` starts a module worker, streams both output channels, and
returns a byte snapshot of the run's in-memory files. Each run starts with its
own filesystem. Use a custom dedicated worker for persistent storage or custom
host imports. Offline audio works in the worker. Live audio runs on the page.
Browser sleep can use `Atomics.wait` in a cross-origin-isolated worker. Other
browser contexts use the host's bounded synchronous fallback.

In a runtime that lacks the Web Worker constructor, pass a compatible worker
as `createGooseWorker({ worker })`. The direct host also runs without a worker.

## Standard library compatibility

| Module | Drop-in compatibility with `stdlib-web` |
| --- | --- |
| `base64` | Same encoding and decoding API |
| `binary` | Same binary reading and writing API |
| `csv` | Same parsing and formatting API |
| `dictionary` | Same dictionary API |
| `exception` | Same Goose exception helpers |
| `ffi` | Reads bytes and C strings at addresses in Wasm linear memory |
| `json` | Same parsing and formatting API, with host float helpers |
| `math` | Same numeric API, with JavaScript implementations of math imports |
| `os` | Files, streams, arguments, and environment come from the host. Memory trimming is a no-op. |
| `regex` | Same regular expression API |
| `slice_pool` | Same allocation API. Trimming zeroes full free pages and retains the backing allocation. |
| `slice_pool_internal` | Same span tree layout and operations, implemented in Goose |
| `slot_pool` | Same slot allocation API |
| `std` | Same helpers, with numeric and byte-search imports supplied by the host |
| `vec` | Same vector API |
| `audio` | Web addition for offline PCM mixing and live Web Audio playback |
| `gfx` | WebGL2 backend + GLSL 450→300 es transpiler + JSPI async frame loop (`asyncFrame: true`, `loaded.runAsync()`) and headless fallback |
| `ui` | Immediate-mode GUI rendered on 2D canvas and composited onto `gfx` |
| `physics` | Pure-JavaScript 3D rigid-body box solver matching Goose's `physics` API |

Custom externs can be supplied through the `imports` option. The browser host
provides JavaScript imports and virtual resources for the direct Wasm ABI.

## Browser demo

From the repository root, substitute `build/bin/goosew` if the compiler is
available there instead of on your path.

```sh
goosew host/web/demo/demo.goose --stdlib stdlib-web --target wasm-direct -O2 -o host/web/demo/demo.wasm
python3 -m http.server 8000
```

Open [the playground](http://localhost:8000/host/web/demo/). The demo shows its
stdout, stderr, and virtual files, and the audio button runs it with
`--play`. You can also drop or choose another direct-Wasm program compiled
with `stdlib-web`.
