import { loadGoose, runGoose, supportsJspi } from "./host/web/index.js";

const $ = (id) => document.getElementById(id);
const stageMedia = $("stage-media");
const codeDisclosure = $("code-disclosure");
const jspi = supportsJspi();
const decoder = new TextDecoder();
const pageTitle = document.title;

let manifest;
let selected;
let canvas;
let activeRun;
let life;
let sourceRequest;
let sourceText;
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

function setMessage(text = "", restartAction = null) {
  const box = $("stage-message");
  box.replaceChildren();
  if (!text && !restartAction) {
    box.hidden = true;
    return;
  }
  if (text) box.append(element("span", text));
  if (restartAction) {
    const button = element("button", "Restart");
    button.type = "button";
    button.addEventListener("click", restartAction);
    box.append(button);
  }
  box.hidden = false;
}

function enqueue(action) {
  queue = queue.then(action).catch((error) => {
    setMessage(error.message, selected ? () => enqueue(() => startRun(selected)) : null);
  });
}

function renderGallery() {
  const groups = [
    ["gpu", "Interactive"],
    ["software", "Software"],
  ];
  for (const [mode, label] of groups) {
    const section = element("section");
    section.append(element("h2", label));
    for (const example of manifest.examples.filter((item) => item.mode === mode)) {
      const link = element("a", example.title);
      link.href = `#${example.id}`;
      link.dataset.example = example.id;
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
  const { width, height } = example.canvas ?? { width: 640, height: 400 };
  canvas = makeCanvas(example.title, width, height, example.mode === "software");
  if (example.mode === "gpu") {
    canvas.tabIndex = 0;
    canvas.style.setProperty("--ratio", `${width} / ${height}`);
    canvas.style.setProperty("--natural-width", `${width}px`);
    canvas.classList.add("gpu-surface");
    canvas.addEventListener("pointerdown", (event) => event.currentTarget.focus({ preventScroll: true }));
  } else {
    canvas.classList.add("sw-single");
    canvas.style.setProperty("--natural-width", `${Math.max(width, 640)}px`);
  }
  stageMedia.replaceChildren(canvas);
}

function showSelection(example) {
  for (const link of $("gallery").querySelectorAll("a")) {
    if (link.dataset.example === example.id) link.setAttribute("aria-current", "true");
    else link.removeAttribute("aria-current");
  }
  $("demo-title").textContent = example.title;
  $("compatibility").hidden = example.mode !== "gpu" || jspi;
  $("code-filename").textContent = example.file;
  $("upstream-source").href = `${manifest.upstreamRepo}/blob/${manifest.upstreamRev}/samples/${example.file}`;
  resetSource();
  freshStage(example);
}

function selectHash() {
  const id = location.hash.slice(1);
  const example = manifest.examples.find((item) => item.id === id) ?? manifest.examples[0];
  if (example.id !== id) history.replaceState(null, "", `#${example.id}`);
  enqueue(async () => {
    if (selected === example) return;
    await stopRun();
    selected = example;
    showSelection(example);
    if (example.mode === "gpu" && !jspi) {
      setMessage("WebAssembly JSPI is required for this GPU example.");
      return;
    }
    await startRun(example);
  });
}

function snapshot(fs) {
  const entries = typeof fs?.snapshot === "function" ? fs.snapshot() : fs ?? {};
  return Object.fromEntries(Object.entries(entries).map(([path, bytes]) => [
    path.startsWith("/") ? path : `/${path}`, bytes,
  ]));
}

function createAutoAudioContext(example) {
  const AudioContext = window.AudioContext ?? window.webkitAudioContext;
  if (!example.tags.includes("audio") || !AudioContext) return { audioContext: undefined, cleanup: null };
  try {
    const audioContext = new AudioContext();
    const unlock = () => {
      if (audioContext.state === "suspended") audioContext.resume().catch(() => {});
    };
    unlock();
    window.addEventListener("pointerdown", unlock, { passive: true });
    window.addEventListener("keydown", unlock, { passive: true });
    return {
      audioContext,
      cleanup: () => {
        window.removeEventListener("pointerdown", unlock);
        window.removeEventListener("keydown", unlock);
      },
    };
  } catch {
    return { audioContext: undefined, cleanup: null };
  }
}

async function startRun(example) {
  let run;
  const { audioContext, cleanup: cleanupAudioUnlock } = createAutoAudioContext(example);
  try {
    if (selected !== example) return;
    await stopRun();
    freshStage(example);
    $("demo-title").textContent = example.title;
    run = { example, audioContext, cleanupAudioUnlock, surface: canvas, stopping: false };
    activeRun = run;
    setMessage("Loading…");

    const wasm = new URL(example.wasmUrl, import.meta.url);
    const options = { args: example.defaultArgs };
    if (example.mode === "gpu") {
      const files = Object.fromEntries(await Promise.all((example.dataFiles ?? []).map(async ({ url, path }) => {
        const response = await fetchAsset(url);
        return [path, new Uint8Array(await response.arrayBuffer())];
      })));
      if (selected !== example) {
        await disposeRun(run);
        return;
      }
      run.loaded = await loadGoose(wasm, {
        ...options,
        canvas: run.surface,
        asyncFrame: true,
        audioContext,
        files,
        resourceDir: "/",
        onTitle: (title) => {
          if (selected === example) $("demo-title").textContent = title || example.title;
        },
      });
      setMessage();
      run.done = executeRun(run, () => run.loaded.runAsync());
    } else {
      run.done = executeRun(run, () => runGoose(wasm, options));
    }
  } catch (error) {
    if (run) await disposeRun(run);
    else {
      cleanupAudioUnlock?.();
      if (audioContext && audioContext.state !== "closed") await audioContext.close().catch(() => {});
    }
    throw error;
  }
}

async function executeRun(run, execute) {
  try {
    const result = await execute();
    if (selected !== run.example) return;
    const files = snapshot(run.loaded?.host.fs ?? result.fs);
    if (result.exitCode !== 0) {
      setMessage(`Exited with code ${result.exitCode}.`, () => enqueue(() => startRun(run.example)));
    } else if (run.example.mode === "software") {
      renderSoftware(run.example, files, result.stdout);
      setMessage();
    } else if (!run.stopping) {
      const png = run.loaded?.host.gfx?.screenshotPngBytes() ?? null;
      if (png) await showLastFrame(run.example, png);
      setMessage("Stopped.", () => enqueue(() => startRun(run.example)));
    }
  } catch (error) {
    if (selected === run.example) {
      setMessage(error.message, () => enqueue(() => startRun(run.example)));
    }
  } finally {
    await disposeRun(run);
  }
}

async function showLastFrame(example, png) {
  const image = await createImageBitmap(new Blob([png], { type: "image/png" }));
  try {
    canvas = makeCanvas(example.title, image.width, image.height);
    canvas.classList.add("gpu-surface");
    canvas.style.setProperty("--ratio", `${image.width} / ${image.height}`);
    canvas.style.setProperty("--natural-width", `${example.canvas?.width ?? image.width}px`);
    canvas.getContext("2d").drawImage(image, 0, 0);
    stageMedia.replaceChildren(canvas);
  } finally {
    image.close();
  }
}

async function disposeRun(run) {
  try {
    run.cleanupAudioUnlock?.();
    if (document.pointerLockElement === run.surface) document.exitPointerLock();
    await run.loaded?.dispose();
  } finally {
    run.loaded = undefined;
    if (run.audioContext && run.audioContext.state !== "closed") {
      await run.audioContext.close().catch(() => {});
    }
    run.surface = undefined;
    run.audioContext = undefined;
    if (activeRun === run) activeRun = undefined;
    document.title = pageTitle;
  }
}

async function stopRun() {
  if (!activeRun) return;
  const run = activeRun;
  run.stopping = true;
  if (run.loaded) run.loaded.host.stop();
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
  const legend = element("figcaption", "Green start · Red goal · Amber path · Blue water · Purple path through water", "maze-legend");
  const figure = element("figure");
  figure.append(legend, stageMedia.firstElementChild);
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
  canvas.classList.add("sw-single");
  canvas.style.setProperty("--natural-width", `${canvas.width}px`);
  life = { frames, index: 0, raf: null };
  $("life-position").max = frames.length - 1;
  $("life-controls").hidden = false;
  displayGeneration(0);
  playLife();
}

function renderSoftware(example, files, stdout) {
  switch (example.renderer) {
    case "ppm": {
      const bytes = files[example.vfsImage];
      if (!bytes) throw new Error("The example produced no raytrace.ppm");
      const image = readNetpbm(bytes);
      canvas = paintImage(image, example.title);
      canvas.classList.add("sw-single");
      canvas.style.setProperty("--natural-width", `${image.width * 2}px`);
      stageMedia.replaceChildren(canvas);
      break;
    }
    case "pgm-grid":
      renderFilters(files);
      break;
    case "life-ascii":
      renderLife(stdout);
      break;
    case "maze-ascii":
      renderMaze(stdout);
      break;
  }
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

function resetSource() {
  sourceRequest?.abort();
  sourceRequest = undefined;
  sourceText = undefined;
  $("copy-source").disabled = true;
  $("source-status").textContent = "";
  $("source-code").replaceChildren();
  if (codeDisclosure.open) loadSource();
}

async function loadSource() {
  if (!selected || sourceText !== undefined || sourceRequest) return;
  const request = new AbortController();
  sourceRequest = request;
  $("source-status").textContent = "Loading…";
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

codeDisclosure.addEventListener("toggle", () => {
  if (codeDisclosure.open) loadSource();
});
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
    if (sourceText === text) $("source-status").textContent = "Clipboard unavailable";
  }
});

try {
  manifest = await (await fetchAsset("./manifest.json")).json();
  renderGallery();
  window.addEventListener("hashchange", selectHash);
  selectHash();
} catch (error) {
  setMessage(error.message);
}
