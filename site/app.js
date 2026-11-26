import { loadGoose, runGoose, supportsJspi } from "./host/web/index.js";

const $ = (id) => document.getElementById(id);
const stageMedia = $("stage-media");
const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
const jspi = supportsJspi();
const decoder = new TextDecoder();
const pageTitle = document.title;
let manifest;
let selected;
let canvas;
let activeRun;
let latestRun;
let life;
let sourceRequest;
let sourceText;
let fileURLs = [];
let queue = Promise.resolve();

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}

function fetchAsset(url, options) {
  return fetch(url, options).then((response) => {
    if (!response.ok) throw new Error(`Could not fetch ${url} (HTTP ${response.status})`);
    return response;
  });
}

function formatSize(bytes) {
  return bytes < 1024 ? `${bytes} B` : `${(bytes / 1024).toFixed(1)} KB`;
}

function message(text = "") {
  $("stage-message").textContent = text;
  $("stage-message").hidden = !text;
}

function enqueue(action) {
  queue = queue.then(action).catch((error) => {
    message(error.message);
    writeConsole("stderr", error.message + "\n");
    updateButtons();
  });
}

function renderGallery() {
  const groups = [
    ["gpu", "Interactive GPU (WebGL2)"],
    ["software", "Software Graphics (Canvas)"],
  ];
  for (const [mode, label] of groups) {
    const section = element("section");
    section.append(element("h2", label));
    for (const example of manifest.examples.filter((item) => item.mode === mode)) {
      const link = element("a");
      link.href = `#${example.id}`;
      link.dataset.example = example.id;
      const tags = element("span", undefined, "tags");
      tags.append(...example.tags.map((tag) => element("span", tag)));
      link.append(element("span", example.title, "example-name"),
        element("span", formatSize(example.wasmBytes), "size"), tags);
      section.append(link);
    }
    $("gallery").append(section);
  }
}

function makeCanvas(label, width, height, pixel = false) {
  const surface = document.createElement("canvas");
  surface.width = width;
  surface.height = height;
  surface.setAttribute("aria-label", label);
  surface.classList.toggle("pixel", pixel);
  return surface;
}

function freshStage(example) {
  stopLife();
  life = undefined;
  $("life-controls").hidden = true;
  const { width, height } = example.canvas ?? { width: 640, height: 360 };
  canvas = makeCanvas(example.title, width, height, example.mode === "software");
  if (example.mode === "gpu") {
    canvas.tabIndex = 0;
    canvas.style.setProperty("--ratio", width / height);
    canvas.classList.add("gpu-surface");
    canvas.addEventListener("pointerdown", (event) => event.currentTarget.focus({ preventScroll: true }));
  }
  stageMedia.replaceChildren(canvas);
}

function showSelection() {
  const example = selected;
  for (const link of $("gallery").querySelectorAll("a")) {
    if (link.dataset.example === example.id) link.setAttribute("aria-current", "true");
    else link.removeAttribute("aria-current");
  }
  $("demo-title").textContent = example.title;
  $("wasm-size").textContent = formatSize(example.wasmBytes);
  $("wasm-size").title = `${example.wasmBytes.toLocaleString()} bytes`;
  $("duration").textContent = "—";
  $("fps").textContent = "—";
  $("compatibility").hidden = example.mode !== "gpu" || jspi;
  $("focus-hint").textContent = example.pointerLock
    ? "Click the canvas to focus and capture the mouse. Press Esc to release Pointer Lock."
    : "Click the canvas to focus keyboard and mouse input.";
  $("focus-hint").hidden = example.mode !== "gpu";
  $("preset").replaceChildren(...(example.presets ?? []).map((preset, index) => new Option(preset.label, index)));
  $("preset-field").hidden = !example.presets;

  $("description").textContent = example.description;
  $("control-list").replaceChildren(...(example.controls?.split(" · ") ?? []).map((control) => element("li", control)));
  const upstream = $("upstream-source");
  upstream.href = `${manifest.upstreamRepo}/blob/${manifest.upstreamRev}/samples/${example.file}`;
  upstream.hidden = false;

  resetSource();
  latestRun = undefined;
  $("console-output").replaceChildren();
  renderFiles();
  freshStage(example);
  message(example.mode === "gpu" && !jspi ? "Choose a software demo to run here." : "Press Run to start.");
  updateButtons();
}

function selectHash() {
  const id = location.hash.slice(1);
  const example = manifest.examples.find((item) => item.id === id) ?? manifest.examples[0];
  if (example.id !== id) history.replaceState(null, "", `#${example.id}`);
  enqueue(async () => {
    if (selected === example) return;
    await stopRun();
    selected = example;
    showSelection();
  });
}

function updateButtons() {
  const gpuAvailable = selected?.mode !== "gpu" || jspi;
  $("run").disabled = !selected || !gpuAvailable;
  $("run").textContent = latestRun ? "Restart" : "Run";
  $("stop").disabled = !activeRun || activeRun.example.mode !== "gpu";
  $("screenshot").disabled = !latestRun?.hasImage && !activeRun?.loaded;
  $("fullscreen").disabled = !selected || !$("stage").requestFullscreen;
}

function writeConsole(stream, text) {
  if (!text) return;
  const consoleOutput = $("console-output");
  const atBottom = consoleOutput.scrollHeight - consoleOutput.scrollTop - consoleOutput.clientHeight < 12;
  if (stream === "stderr") consoleOutput.append(element("span", text, "stderr"));
  else consoleOutput.append(document.createTextNode(text));
  if (atBottom) consoleOutput.scrollTop = consoleOutput.scrollHeight;
}

function streamOutput(stream) {
  return (bytes, text) => writeConsole(stream, text ?? (typeof bytes === "string" ? bytes : decoder.decode(bytes)));
}

function snapshot(fs) {
  const entries = typeof fs?.snapshot === "function" ? fs.snapshot() : fs ?? {};
  return Object.fromEntries(Object.entries(entries).map(([path, bytes]) => [
    path.startsWith("/") ? path : `/${path}`, bytes,
  ]));
}

function gpuScreenshot(run) {
  return run.loaded?.host.gfx?.screenshotPngBytes() ?? null;
}

function updateFps(run) {
  const now = performance.now();
  run.frames++;
  if (now - run.fpsStart < 500) return;
  $("fps").textContent = (run.frames * 1000 / (now - run.fpsStart)).toFixed(0);
  run.frames = 0;
  run.fpsStart = now;
}

async function startRun(example, preset, audioContext) {
  let run;
  try {
    if (selected !== example) return;
    await stopRun();
    freshStage(example);
    $("console-output").replaceChildren();
    $("demo-title").textContent = example.title;
    $("fps").textContent = "—";
    $("duration").textContent = "—";
    run = { example, audioContext, files: {}, start: performance.now(), surface: canvas };
    latestRun = activeRun = run;
    renderFiles();
    updateButtons();
    message("Loading WebAssembly…");

    const wasm = new URL(example.wasmUrl, import.meta.url);
    const options = {
      args: preset?.args ?? example.defaultArgs,
      onStdout: streamOutput("stdout"),
      onStderr: streamOutput("stderr"),
    };
    if (example.mode === "gpu") {
      const files = Object.fromEntries(await Promise.all((example.dataFiles ?? []).map(async ({ url, path }) => {
        const response = await fetchAsset(url);
        return [path, new Uint8Array(await response.arrayBuffer())];
      })));
      run.loaded = await loadGoose(wasm, {
        ...options,
        canvas: run.surface,
        asyncFrame: true,
        audioContext,
        files,
        resourceDir: "/",
        onTitle: (title) => { $("demo-title").textContent = title || example.title; },
        onFrame: () => updateFps(run),
      });
      run.loadMs = performance.now() - run.start;
      run.fpsStart = performance.now();
      run.frames = 0;
      $("duration").textContent = `${run.loadMs.toFixed(1)} ms / …`;
      message();
      updateButtons();
      run.done = executeRun(run, () => run.loaded.runAsync());
    } else {
      run.done = executeRun(run, () => runGoose(wasm, options));
    }
  } catch (error) {
    if (run) await disposeRun(run);
    throw error;
  } finally {
    if (!run && audioContext && audioContext.state !== "closed") await audioContext.close();
  }
}

async function executeRun(run, execute) {
  try {
    const result = await execute();
    run.finishing = true;
    run.files = snapshot(run.loaded?.host.fs ?? result.fs);
    const runMs = result.durationMs ?? performance.now() - run.start;
    const loadMs = run.loadMs ?? Math.max(0, performance.now() - run.start - runMs);
    $("duration").textContent = `${loadMs.toFixed(1)} / ${runMs.toFixed(1)} ms`;

    if (result.exitCode !== 0) {
      message(`Exited with code ${result.exitCode}. See Console for output.`);
    } else if (run.example.mode === "software") {
      renderSoftware(run, result.stdout);
      run.hasImage = true;
      message();
    } else {
      run.png ??= gpuScreenshot(run) ?? Object.entries(run.files).find(([path]) => path.endsWith(".png"))?.[1];
      run.hasImage = Boolean(run.png);
      if (run.png) await showLastFrame(run);
      message(run.hasImage ? "" : "Demo stopped. Press Restart to play again.");
    }
  } catch (error) {
    run.finishing = true;
    message(error.message);
    writeConsole("stderr", error.message + "\n");
  } finally {
    await disposeRun(run);
  }
}

async function showLastFrame(run) {
  const image = await createImageBitmap(new Blob([run.png], { type: "image/png" }));
  try {
    canvas = makeCanvas(run.example.title, image.width, image.height);
    canvas.getContext("2d").drawImage(image, 0, 0);
    stageMedia.replaceChildren(canvas);
  } finally {
    image.close();
  }
}

async function disposeRun(run) {
  try {
    if (document.pointerLockElement === run.surface) document.exitPointerLock();
    await run.loaded?.dispose();
  } catch (error) {
    writeConsole("stderr", error.message + "\n");
  } finally {
    run.loaded = undefined;
    try {
      if (run.audioContext && run.audioContext.state !== "closed") await run.audioContext.close();
    } catch (error) {
      writeConsole("stderr", error.message + "\n");
    }
    if (run.example.mode === "gpu" && canvas === run.surface) freshStage(run.example);
    run.surface = undefined;
    run.audioContext = undefined;
    activeRun = undefined;
    document.title = pageTitle;
    $("fps").textContent = "—";
    renderFiles();
    updateButtons();
  }
}

async function stopRun() {
  if (!activeRun) return;
  const run = activeRun;
  if (run.loaded && !run.finishing) {
    try {
      run.png = gpuScreenshot(run);
    } catch (error) {
      writeConsole("stderr", error.message + "\n");
    }
    run.loaded.host.stop();
  }
  await run.done;
}

function readNetpbm(bytes) {
  let offset = 0;
  const whitespace = (byte) => byte === 32 || (byte >= 9 && byte <= 13);
  function token() {
    while (offset < bytes.length) {
      if (whitespace(bytes[offset])) offset++;
      else if (bytes[offset] === 35) {
        while (offset < bytes.length && bytes[offset] !== 10 && bytes[offset] !== 13) offset++;
      } else break;
    }
    const start = offset;
    while (offset < bytes.length && !whitespace(bytes[offset]) && bytes[offset] !== 35) offset++;
    return decoder.decode(bytes.subarray(start, offset));
  }
  function integer(text, min, max) {
    const value = Number(text);
    if (!/^\d+$/.test(text) || !Number.isSafeInteger(value) || value < min || value > max) {
      throw new Error("Invalid Netpbm integer");
    }
    return value;
  }

  const magic = token();
  if (!["P2", "P3", "P5", "P6"].includes(magic)) throw new Error("Unsupported Netpbm format");
  const width = integer(token(), 1, 16384);
  const height = integer(token(), 1, 16384);
  if (width * height > 16777216) throw new Error("Netpbm image is too large");
  const max = integer(token(), 1, 65535);
  const binary = magic === "P5" || magic === "P6";
  const color = magic === "P3" || magic === "P6";
  const wide = max > 255;
  if (binary) {
    const length = width * height * (color ? 3 : 1) * (wide ? 2 : 1);
    if (!whitespace(bytes[offset])) throw new Error("Missing Netpbm raster delimiter");
    // Read only the delimiter. A leading raster byte can itself be whitespace or '#'.
    if (bytes[offset++] === 13 && bytes[offset] === 10 && bytes.length - offset > length) offset++;
    if (bytes.length - offset < length) throw new Error("Truncated Netpbm raster");
  }
  const rgba = new Uint8ClampedArray(width * height * 4);
  function sample() {
    if (!binary) return integer(token(), 0, max) * 255 / max;
    const first = bytes[offset++];
    const value = wide ? first * 256 + bytes[offset++] : first;
    return value * 255 / max;
  }
  for (let i = 0; i < rgba.length; i += 4) {
    const first = sample();
    rgba[i] = first;
    rgba[i + 1] = color ? sample() : first;
    rgba[i + 2] = color ? sample() : first;
    rgba[i + 3] = 255;
  }
  return new ImageData(rgba, width, height);
}

function paintImage(image, title) {
  const surface = makeCanvas(title, image.width, image.height, true);
  surface.getContext("2d").putImageData(image, 0, 0);
  return surface;
}

function showGrid(items) {
  const grid = element("div", undefined, "stage-grid");
  for (const [caption, surface] of items) {
    const figure = element("figure");
    figure.append(element("figcaption", caption), surface);
    grid.append(figure);
  }
  stageMedia.replaceChildren(grid);
}

function filterOriginal(width, height) {
  // The pinned sample only writes blurred.pgm and edges.pgm. Replay its seeded input.
  let seed = 99n;
  const rejectionFloor = (1n << 64n) % 21n;
  function nextRandom() {
    seed = BigInt.asUintN(64, seed + 11400714819323198485n);
    let z = BigInt.asUintN(64, (seed ^ (seed >> 30n)) * 13787848793156543929n);
    z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 10723151780598845931n);
    return z ^ (z >> 31n);
  }
  const rgba = new Uint8ClampedArray(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const dx = x - width / 2;
      const dy = y - height / 2;
      const distance = Math.sqrt(dx * dx + dy * dy);
      let value = distance < 60 ? 230 : 96 + 64 * Math.sin(distance / 12) + x / width * 60;
      if ((Math.trunc(x / 64) + Math.trunc(y / 64)) % 2 === 0 && y > height * 3 / 4) value = 40;
      let noise = nextRandom();
      while (noise < rejectionFloor) noise = nextRandom();
      value = Math.trunc(Math.max(0, Math.min(255, value + Number(noise % 21n) - 10)));
      const i = (y * width + x) * 4;
      rgba[i] = rgba[i + 1] = rgba[i + 2] = value;
      rgba[i + 3] = 255;
    }
  }
  return new ImageData(rgba, width, height);
}

function renderFilters(files) {
  const filename = (path) => path.split("/").at(-1).replace(/\.pgm$/i, "");
  const labels = { original: "Original", blurred: "Box blur", edges: "Sobel edges" };
  const images = Object.entries(files).filter(([path]) => /\.pgm$/i.test(path)).map(([path, bytes]) => [
    filename(path), readNetpbm(bytes),
  ]);
  if (!images.length) throw new Error("The example produced no PGM files");
  if (!images.some(([name]) => name === "original")) {
    const { width, height } = images[0][1];
    images.push(["original", filterOriginal(width, height)]);
  }
  const order = Object.keys(labels);
  images.sort(([a], [b]) => (order.includes(a) ? order.indexOf(a) : order.length) -
    (order.includes(b) ? order.indexOf(b) : order.length));
  showGrid(images.map(([name, image]) => [labels[name] ?? name, paintImage(image, labels[name] ?? name)]));
}

function parseGrids(text, heading, rowPattern) {
  const grids = [];
  let grid;
  for (const line of text.split(/\r?\n/)) {
    if (heading.test(line)) {
      grid = { label: line, rows: [] };
      grids.push(grid);
    } else if (grid && rowPattern.test(line)) {
      grid.rows.push(line);
    } else {
      grid = undefined;
    }
  }
  if (!grids.length || grids.some(({ rows }) => !rows.length || rows.some((row) => row.length !== rows[0].length))) {
    throw new Error("Could not read grids from Goose stdout");
  }
  return grids;
}

function drawGrid(surface, rows, colors, cell, gap = 1) {
  const context = surface.getContext("2d");
  context.fillStyle = "#22222d";
  context.fillRect(0, 0, surface.width, surface.height);
  rows.forEach((row, y) => {
    Array.from(row).forEach((value, x) => {
      context.fillStyle = colors[value];
      context.fillRect(x * cell, y * cell, cell - gap, cell - gap);
    });
  });
}

function renderMaze(text) {
  const grids = parseGrids(text, /^(BFS|Dijkstra):/, /^[#.*~oSE]+$/);
  const colors = { "#": "#3d4256", ".": "#151820", "*": "#ffca85", "~": "#285a81",
    o: "#ae8bff", S: "#6ce1a6", E: "#ff8b8b" };
  const items = grids.map(({ label, rows }) => {
    const cell = 24;
    const surface = makeCanvas(label, rows[0].length * cell, rows.length * cell, true);
    drawGrid(surface, rows, colors, cell);
    return [label, surface];
  });
  showGrid(items);
  const legend = element("figcaption", "Green start · Red goal · Amber path · Blue water · Purple path through water");
  const figure = element("figure");
  figure.append(legend, stageMedia.firstElementChild);
  figure.style.width = "100%";
  legend.className = "maze-legend";
  stageMedia.replaceChildren(figure);
}

function displayGeneration(index) {
  const { label, rows } = life.frames[index];
  life.index = index;
  $("life-position").value = index;
  $("life-position").setAttribute("aria-valuetext", label);
  $("life-label").textContent = label;
  drawGrid(canvas, rows, { ".": "#151820", "#": "#a5f4ba" }, 40, 2);
}

function stopLife() {
  if (!life) return;
  cancelAnimationFrame(life.raf);
  life.raf = null;
  $("life-play").textContent = "Play";
}

function playLife() {
  $("life-play").textContent = "Pause";
  let last = performance.now();
  function step(now) {
    if (now - last >= 360) {
      displayGeneration((life.index + 1) % life.frames.length);
      last = now;
    }
    life.raf = requestAnimationFrame(step);
  }
  life.raf = requestAnimationFrame(step);
}

function renderLife(text) {
  const frames = parseGrids(text, /^generation \d+, population \d+$/, /^[.#]+$/);
  const rows = frames[0].rows;
  canvas.width = rows[0].length * 40;
  canvas.height = rows.length * 40;
  life = { frames, index: 0, raf: null };
  $("life-position").max = frames.length - 1;
  $("life-controls").hidden = false;
  displayGeneration(0);
  playLife();
}

function renderSoftware(run, stdout) {
  switch (run.example.renderer) {
    case "ppm": {
      const bytes = run.files[run.example.vfsImage];
      if (!bytes) throw new Error("The example produced no raytrace.ppm");
      canvas = paintImage(readNetpbm(bytes), run.example.title);
      stageMedia.replaceChildren(canvas);
      break;
    }
    case "pgm-grid":
      renderFilters(run.files);
      break;
    case "life-ascii":
      renderLife(stdout);
      break;
    case "maze-ascii":
      renderMaze(stdout);
      break;
  }
}

function activateTab(tab) {
  for (const item of tabs) {
    const active = item === tab;
    item.setAttribute("aria-selected", String(active));
    item.tabIndex = active ? 0 : -1;
    $(item.getAttribute("aria-controls")).hidden = !active;
  }
  if (tab.id === "tab-source") loadSource();
  if (tab.id === "tab-files") renderFiles();
}

function resetSource() {
  sourceRequest?.abort();
  sourceRequest = undefined;
  sourceText = undefined;
  $("copy-source").disabled = true;
  $("source-status").textContent = "";
  $("source-code").replaceChildren();
  if (!$("source").hidden) loadSource();
}

const GOOSE_KEYWORDS = new Set([
  "as", "break", "case", "const", "continue", "default", "defer", "else", "enum", "extern",
  "false", "fn", "for", "from", "guard", "if", "import", "in", "let", "match", "namespace",
  "null", "return", "struct", "true", "type", "union", "var", "while", "block", "assert",
]);
const GOOSE_TYPES = new Set([
  "bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64",
  "int2", "int3", "int4", "float2", "float3", "float4", "mat4", "void",
]);
const GOOSE_TOKEN = /(\/\/.*$)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(\b0x[0-9a-fA-F_]+\b|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(\b[A-Za-z_][A-Za-z0-9_]*\b)/g;

function highlightGooseLine(line) {
  const fragment = document.createDocumentFragment();
  let last = 0;
  for (const match of line.matchAll(GOOSE_TOKEN)) {
    if (match.index > last) fragment.append(document.createTextNode(line.slice(last, match.index)));
    const [text, comment, str, num, ident] = match;
    let cls;
    if (comment) cls = "tok-co";
    else if (str) cls = "tok-st";
    else if (num) cls = "tok-nu";
    else if (ident) {
      if (GOOSE_KEYWORDS.has(ident)) cls = "tok-kw";
      else if (GOOSE_TYPES.has(ident)) cls = "tok-ty";
    }
    fragment.append(cls ? element("span", text, cls) : document.createTextNode(text));
    last = match.index + text.length;
  }
  if (last < line.length) fragment.append(document.createTextNode(line.slice(last)));
  return fragment;
}

async function loadSource() {
  if (!selected || sourceText !== undefined || sourceRequest) return;
  const request = new AbortController();
  sourceRequest = request;
  $("source-status").textContent = "Loading source…";
  try {
    const response = await fetchAsset(selected.sourceUrl, { signal: request.signal });
    const text = await response.text();
    if (request.signal.aborted) return;
    sourceText = text;
    const lines = text.split(/\r?\n/);
    if (lines.at(-1) === "") lines.pop();
    const listing = document.createDocumentFragment();
    lines.forEach((line, i) => {
      const row = element("code", undefined, "source-line");
      const number = element("span", i + 1, "line-number");
      number.setAttribute("aria-hidden", "true");
      row.append(number, highlightGooseLine(line));
      listing.append(row);
    });
    $("source-code").replaceChildren(listing);
    $("copy-source").disabled = false;
    $("source-status").textContent = `${lines.length} lines`;
  } catch (error) {
    if (!request.signal.aborted) $("source-status").textContent = error.message;
  } finally {
    if (sourceRequest === request) sourceRequest = undefined;
  }
}

function download(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = element("a");
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function previewFile(path, bytes, preview) {
  const extension = path.split(".").at(-1).toLowerCase();
  if (extension === "png") {
    const image = element("img");
    image.alt = path;
    image.src = URL.createObjectURL(new Blob([bytes], { type: "image/png" }));
    fileURLs.push(image.src);
    preview.append(image);
  } else if (extension === "ppm" || extension === "pgm") {
    preview.append(paintImage(readNetpbm(bytes), path));
  } else {
    const shown = bytes.subarray(0, 128);
    const hex = Array.from(shown, (value) => value.toString(16).padStart(2, "0"));
    const rows = [];
    for (let i = 0; i < hex.length; i += 16) rows.push(hex.slice(i, i + 16).join(" "));
    if (shown.length < bytes.length) rows.push("…");
    preview.append(element("pre", rows.join("\n") || "Empty file"));
  }
}

function renderFiles() {
  for (const url of fileURLs) URL.revokeObjectURL(url);
  fileURLs = [];
  const list = $("file-list");
  list.replaceChildren();
  $("refresh-files").disabled = !latestRun;
  if (!latestRun) {
    list.append(element("p", "Run the example to inspect its virtual files."));
    return;
  }
  // Avoid copying large VFS assets on every frame. Refresh on demand while a demo runs.
  const files = latestRun.loaded ? snapshot(latestRun.loaded.host.fs) : latestRun.files;
  const entries = Object.entries(files).sort(([a], [b]) => a.localeCompare(b));
  if (!entries.length) list.append(element("p", "No files in the virtual filesystem."));
  for (const [path, bytes] of entries) {
    const row = element("details", undefined, "file");
    const summary = element("summary", `${path} · ${formatSize(bytes.byteLength)}`);
    const preview = element("div", undefined, "file-preview");
    const button = element("button", "Download");
    button.addEventListener("click", () => download(new Blob([bytes]), path.split("/").at(-1)));
    preview.append(button);
    row.addEventListener("toggle", function renderPreview() {
      if (!row.open) return;
      row.removeEventListener("toggle", renderPreview);
      try {
        previewFile(path, bytes, preview);
      } catch (error) {
        preview.append(element("p", error.message));
      }
    });
    row.append(summary, preview);
    list.append(row);
  }
}

function screenshotCanvas() {
  const surfaces = Array.from(stageMedia.querySelectorAll("canvas"));
  if (surfaces.length === 1) return surfaces[0];
  const gap = 12;
  const width = surfaces.reduce((total, surface) => total + surface.width + gap, gap);
  const height = Math.max(...surfaces.map((surface) => surface.height)) + 44;
  const composite = makeCanvas("Stage screenshot", width, height);
  const context = composite.getContext("2d");
  context.fillStyle = "#f6f8fa";
  context.fillRect(0, 0, width, height);
  context.fillStyle = "#1f2328";
  context.font = "600 15px -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
  let x = gap;
  for (const surface of surfaces) {
    context.fillText(surface.getAttribute("aria-label"), x, 24, surface.width);
    context.drawImage(surface, x, 32);
    x += surface.width + gap;
  }
  return composite;
}

async function takeScreenshot() {
  const run = latestRun;
  try {
    const bytes = gpuScreenshot(run) ?? run.png;
    const blob = bytes ? new Blob([bytes], { type: "image/png" })
      : await new Promise((resolve) => screenshotCanvas().toBlob(resolve, "image/png"));
    if (!blob) throw new Error("Could not capture the current canvas");
    download(blob, `${run.example.id}.png`);
  } catch (error) {
    writeConsole("stderr", error.message + "\n");
  }
}

$("run").addEventListener("click", () => {
  const example = selected;
  const preset = example.presets?.[$("preset").value];
  let audioContext;
  const AudioContext = window.AudioContext ?? window.webkitAudioContext;
  if (example.tags.includes("audio") && AudioContext) {
    // Resume during the user gesture, before fetching the WAD or Wasm.
    try {
      audioContext = new AudioContext();
      audioContext.resume().catch((error) => writeConsole("stderr", error.message + "\n"));
    } catch (error) {
      writeConsole("stderr", error.message + "\n");
    }
  }
  enqueue(() => startRun(example, preset, audioContext));
});
$("stop").addEventListener("click", () => enqueue(stopRun));
$("fullscreen").addEventListener("click", async () => {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await $("stage").requestFullscreen();
  } catch (error) {
    writeConsole("stderr", error.message + "\n");
  }
});
$("screenshot").addEventListener("click", takeScreenshot);
$("refresh-files").addEventListener("click", renderFiles);
$("life-play").addEventListener("click", () => {
  if (life.raf === null) playLife();
  else stopLife();
});
$("life-position").addEventListener("input", (event) => {
  stopLife();
  displayGeneration(Number(event.target.value));
});
$("copy-source").addEventListener("click", async () => {
  const text = sourceText;
  try {
    await navigator.clipboard.writeText(text);
    if (sourceText === text) $("source-status").textContent = "Copied";
  } catch {
    if (sourceText === text) $("source-status").textContent = "Clipboard unavailable. Select and copy the source.";
  }
});

tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => activateTab(tab));
  tab.addEventListener("keydown", (event) => {
    const target = {
      ArrowLeft: (index + tabs.length - 1) % tabs.length,
      ArrowRight: (index + 1) % tabs.length,
      Home: 0,
      End: tabs.length - 1,
    }[event.key];
    if (target === undefined) return;
    event.preventDefault();
    tabs[target].focus();
    activateTab(tabs[target]);
  });
});

try {
  manifest = await (await fetchAsset("./manifest.json")).json();
  $("repository").href = manifest.upstreamRepo;
  $("repository").title = `Upstream revision ${manifest.upstreamRev}`;
  if ($("build-rev")) $("build-rev").textContent = manifest.upstreamRev.slice(0, 8);
  renderGallery();
  window.addEventListener("hashchange", selectHash);
  selectHash();
} catch (error) {
  message(error.message);
}
