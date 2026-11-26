const decoder = new TextDecoder("utf-8", { ignoreBOM: true });
const SCREEN = 1;
const SCREEN_DEPTH = 2;
const VERTEX = 0;
const FRAGMENT = 1;
const FLOAT = 0x1406;
const INT = 0x1404;
const UNSIGNED_INT = 0x1405;

// WebGL enum values are also needed when reflecting shaders without a context.
const vertexFormats = [
  null, [1, FLOAT, 4], [2, FLOAT, 8], [3, FLOAT, 12], [4, FLOAT, 16],
  [4, 0x1401, 4, true], [4, 0x1401, 4], [2, 0x1402, 4, true],
  [2, 0x140b, 4], [4, 0x140b, 8],
];
const shaderHeader = `#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp sampler2DShadow;
`;

function transpileShader(bytes, stage) {
  const prefix = `GWEB\0${stage}\0`;
  const text = decoder.decode(bytes);
  if (!text.startsWith(prefix)) throw new Error(`Expected an embedded ${stage} shader`);

  const attributes = [];
  const blocks = [];
  const samplers = [];
  let source = text.slice(prefix.length)
    .replace(/^\s*#version[^\n]*/m, "")
    .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (comment) => comment.replace(/[^\n]/g, " "))
    .replace(/\bgl_VertexIndex\b/g, "gl_VertexID")
    .replace(/\bgl_InstanceIndex\b/g, "gl_InstanceID");
  source = source.replace(/layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*((?:(?:flat|smooth|centroid|highp|mediump|lowp)\s+)*)(in|out)\s+((?:(?:highp|mediump|lowp)\s+)?)(\w+)/g,
    (declaration, location, qualifiers, direction, precision, type) => {
      if (stage === "vert" && direction === "in") attributes.push({ location: Number(location), type });
      if (stage === "vert" ? direction === "out" : direction === "in") {
        return `${qualifiers}${direction} ${precision}${type}`;
      }
      return declaration;
    });
  const shaderStage = stage === "vert" ? VERTEX : FRAGMENT;
  const uniformNames = new Map();
  const resource = /layout\s*\(([^()]*)\)\s*uniform\s+(\w+)\s*(?:\{([^{}]*)\}|(\w+))\s*;/g;
  source = source.replace(resource, (declaration, layout, type, members, name) => {
    const binding = /\bbinding\s*=\s*(\d+)/.exec(layout);
    if (!binding) return declaration;
    const slot = Number(binding[1]);
    if (members !== undefined) {
      // WebGL links both stages together and forbids identically named
      // members in different anonymous blocks (for example view_proj).
      const blockName = `_goose_${stage}_${type}`;
      const instanceName = `${blockName}_data`;
      for (const member of members.split(";")) {
        const field = /\b(\w+)\s*(?:\[[^\]]*\]\s*)*$/.exec(member);
        if (field) uniformNames.set(field[1], `${instanceName}.${field[1]}`);
      }
      blocks.push({ name: blockName, point: shaderStage * 8 + slot });
      return `layout(std140) uniform ${blockName} {${members}} ${instanceName};`;
    }
    if (type !== "sampler2D" && type !== "sampler2DShadow") {
      throw new Error(`Unsupported shader resource ${type}`);
    }
    const samplerName = `_goose_${stage}_${name}`;
    uniformNames.set(name, samplerName);
    samplers.push({ stage: shaderStage, slot, name: samplerName });
    return `uniform ${type} ${samplerName};`;
  });
  if (uniformNames.size) {
    const references = new RegExp(`(\\.\\s*)?\\b(${[...uniformNames.keys()].join("|")})\\b`, "g");
    // Skip declarations and field selections on local vectors and structs.
    source = source.replace(/layout\(std140\) uniform \w+ \{[^{}]*\}\s*\w+;|[^]+?(?=layout\(std140\) uniform |$)/g,
      (part) => part.startsWith("layout(std140) uniform ") ? part :
        part.replace(references, (reference, dot, name) => dot ? reference : uniformNames.get(name)));
  }
  if (stage === "vert") {
    source = source.replace(/\bvoid\s+main\s*\(\s*(?:void\s*)?\)/, "void _goose_main()");
    source += `
uniform float _goose_flip_y;
void main() {
    _goose_main();
    gl_Position.y *= _goose_flip_y;
    gl_Position.z = gl_Position.z * 2.0 - gl_Position.w;
}
`;
  }
  attributes.sort((a, b) => a.location - b.location);
  return { source: shaderHeader + source, attributes, blocks, samplers };
}

function vertexLayout(attributes, formats, instanceLocation) {
  const strides = [0, 0];
  const layout = attributes.map(({ location, type }) => {
    const match = /^(?:(float|int|uint)|([iu]?)vec([234]))$/.exec(type);
    if (!match) throw new Error(`Unsupported vertex type ${type}`);
    const components = Number(match[3] ?? 1);
    const integer = type.startsWith("i") || type.startsWith("u");
    const scalar = type.startsWith("i") ? INT : type.startsWith("u") ? UNSIGNED_INT : FLOAT;
    const format = formats[location] || 0;
    if (format && !vertexFormats[format]) throw new Error(`Invalid vertex format at location ${location}`);
    const [count, dataType, bytes, normalized = false] =
      vertexFormats[format] ?? [components, scalar, components * 4];
    const slot = Number(instanceLocation >= 0 && location >= instanceLocation);
    const offset = strides[slot];
    strides[slot] += bytes;
    return { location, slot, offset, count, type: dataType, normalized, integer };
  });
  return { layout, strides };
}

function linkProgram(gl, vertex, fragment) {
  function compile(type, source) {
    const shader = gl.createShader(type);
    if (!shader) throw new Error("Could not allocate a shader");
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    return shader;
  }
  const program = gl.createProgram();
  if (!program) throw new Error("Could not allocate a shader program");
  const shaders = [];
  try {
    shaders.push(compile(gl.VERTEX_SHADER, vertex), compile(gl.FRAGMENT_SHADER, fragment));
    for (const shader of shaders) gl.attachShader(program, shader);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      const logs = [...shaders.map((shader) => gl.getShaderInfoLog(shader)), gl.getProgramInfoLog(program)];
      throw new Error(logs.filter(Boolean).join("\n") || "Could not link shader program");
    }
    return program;
  } catch (error) {
    gl.deleteProgram(program);
    throw error;
  } finally {
    for (const shader of shaders) gl.deleteShader(shader);
  }
}

const crcTable = Uint32Array.from({ length: 256 }, (_, byte) => {
  for (let i = 0; i < 8; i++) byte = (byte >>> 1) ^ ((byte & 1) ? 0xedb88320 : 0);
  return byte;
});

function encodePng(width, height, rgba) {
  const rowBytes = width * 4;
  const raw = new Uint8Array((rowBytes + 1) * height);
  for (let y = 0; y < height; y++) {
    raw.set(rgba.subarray(y * rowBytes, (y + 1) * rowBytes), y * (rowBytes + 1) + 1);
  }
  const blocks = Math.ceil(raw.length / 65535);
  const zlib = new Uint8Array(2 + raw.length + blocks * 5 + 4);
  zlib.set([0x78, 0x01]);
  const zview = new DataView(zlib.buffer);
  let at = 2;
  let a = 1;
  let b = 0;
  for (let start = 0; start < raw.length; start += 65535) {
    const length = Math.min(65535, raw.length - start);
    const end = start + length;
    zlib[at++] = Number(end === raw.length);
    zview.setUint16(at, length, true);
    zview.setUint16(at + 2, ~length, true);
    at += 4;
    zlib.set(raw.subarray(start, end), at);
    at += length;
    for (let i = start; i < end; i++) {
      a += raw[i];
      if (a >= 65521) a -= 65521;
      b += a;
      if (b >= 65521) b -= 65521;
    }
  }
  zview.setUint32(at, (b << 16) | a);

  const png = new Uint8Array(8 + 12 * 3 + 13 + zlib.length);
  png.set([137, 80, 78, 71, 13, 10, 26, 10]);
  const view = new DataView(png.buffer);
  at = 8;
  function chunk(type, data) {
    view.setUint32(at, data.length);
    view.setUint32(at + 4, type);
    png.set(data, at + 8);
    let crc = 0xffffffff;
    for (let i = at + 4; i < at + 8 + data.length; i++) {
      crc = (crc >>> 8) ^ crcTable[(crc ^ png[i]) & 255];
    }
    view.setUint32(at + 8 + data.length, crc ^ 0xffffffff);
    at += 12 + data.length;
  }
  const header = new Uint8Array(13);
  const info = new DataView(header.buffer);
  info.setUint32(0, width);
  info.setUint32(4, height);
  header.set([8, 6], 8); // RGBA8
  chunk(0x49484452, header); // IHDR
  chunk(0x49444154, zlib);   // IDAT
  chunk(0x49454e44, new Uint8Array()); // IEND
  return png;
}

const keyNames = new Map();
const browserKeys = new Map();
function defineKey(name, scancode, code, keycode = 0x40000000 | scancode) {
  const key = { name, scancode, keycode };
  keyNames.set(name.toLowerCase(), key);
  if (code) browserKeys.set(code, key);
}
for (let i = 0; i < 26; i++) {
  const letter = String.fromCharCode(65 + i);
  defineKey(letter, 4 + i, `Key${letter}`, 97 + i);
}
for (let i = 0; i < 10; i++) {
  const digit = String((i + 1) % 10);
  defineKey(digit, 30 + i, `Digit${digit}`, digit.charCodeAt(0));
}
for (let i = 0; i < 12; i++) defineKey(`F${i + 1}`, 58 + i, `F${i + 1}`);
for (const [name, scan, code, keycode] of [
  ["Return", 40, "Enter", 13], ["Escape", 41, "Escape", 27],
  ["Backspace", 42, "Backspace", 8], ["Tab", 43, "Tab", 9], ["Space", 44, "Space", 32],
  ["-", 45, "Minus", 45], ["=", 46, "Equal", 61], ["[", 47, "BracketLeft", 91],
  ["]", 48, "BracketRight", 93], ["\\", 49, "Backslash", 92], [";", 51, "Semicolon", 59],
  ["'", 52, "Quote", 39], ["`", 53, "Backquote", 96], [",", 54, "Comma", 44],
  [".", 55, "Period", 46], ["/", 56, "Slash", 47], ["Caps Lock", 57, "CapsLock"],
  ["Print Screen", 70, "PrintScreen"], ["Scroll Lock", 71, "ScrollLock"], ["Pause", 72, "Pause"],
  ["Insert", 73, "Insert"], ["Home", 74, "Home"], ["PageUp", 75, "PageUp"],
  ["Delete", 76, "Delete", 127], ["End", 77, "End"], ["PageDown", 78, "PageDown"],
  ["Right", 79, "ArrowRight"], ["Left", 80, "ArrowLeft"], ["Down", 81, "ArrowDown"],
  ["Up", 82, "ArrowUp"], ["Keypad Enter", 88, "NumpadEnter"],
  ["Left Ctrl", 224, "ControlLeft"], ["Left Shift", 225, "ShiftLeft"],
  ["Left Alt", 226, "AltLeft"], ["Left GUI", 227, "MetaLeft"],
  ["Right Ctrl", 228, "ControlRight"], ["Right Shift", 229, "ShiftRight"],
  ["Right Alt", 230, "AltRight"], ["Right GUI", 231, "MetaRight"],
]) defineKey(name, scan, code, keycode);

function freshInput(focused = false) {
  return {
    focused, inWindow: false, x: 0, y: 0, dx: 0, dy: 0, wheelX: 0, wheelY: 0,
    keysDown: new Set(), keysPressed: new Set(), keysReleased: new Set(),
    mouseDown: new Set(), mousePressed: new Set(), mouseReleased: new Set(),
    events: [], text: "",
  };
}

export function createGfxImports(mem, options = {}) {
  const canvas = options.canvas ?? null;
  const document = canvas?.ownerDocument;
  const window = document?.defaultView;
  let gl = null;
  let opened = false;
  let headless = false;
  let stopped = false;
  let quitting = false;
  let flags = 0;
  let lastError = "";
  let clipboard = "";
  let textInput = false;
  let width = 0;
  let height = 0;
  let density = 1;
  let start = 0;
  let previous = 0;
  let elapsed = 0;
  let dt = 0;
  let frameCount = 0;
  let input = freshInput();
  let snapshot = input;
  let relativeWanted = false;
  let locked = false;
  let lockPending = false;
  let pointerLockGeneration = 0;
  let pendingFrame = null;
  const listeners = [];
  const now = () => performance.now();

  const buffers = new Map();
  const textures = new Map();
  const samplers = new Map();
  const pipelines = new Map();
  const uniformBuffers = new Map();
  let nextId = SCREEN_DEPTH + 1;
  let screenPixels = null;
  let passFramebuffer = null;
  let readFramebuffer = null;
  let emptyVao = null;
  let overlay = null;
  let pass = null;
  let pipeline = null;
  let indexBinding = null;
  const vertexBindings = [null, null];
  const targetBindings = new Map();
  let verticesDirty = true;

  function fail(message) {
    lastError = message;
    return 0;
  }

  function handle(resources, id) {
    return resources.get(id >>> 0);
  }

  function storeResource(resources, resource) {
    const id = nextId++;
    resources.set(id, resource);
    return id;
  }

  function release(resources, id, deleteObject) {
    const resource = handle(resources, id);
    if (!resource) return;
    deleteObject?.call(gl, resource.object);
    resources.delete(id >>> 0);
  }

  function queryKey(args, set) {
    const name = decoder.decode(mem.readSliceView(args).view);
    return set.has(keyNames.get(name.toLowerCase())?.name);
  }

  function modifiers() {
    const keys = input.keysDown;
    return (keys.has("Left Shift") ? 0x0001 : 0) | (keys.has("Right Shift") ? 0x0002 : 0) |
      (keys.has("Left Ctrl") ? 0x0040 : 0) | (keys.has("Right Ctrl") ? 0x0080 : 0) |
      (keys.has("Left Alt") ? 0x0100 : 0) | (keys.has("Right Alt") ? 0x0200 : 0) |
      (keys.has("Left GUI") ? 0x0400 : 0) | (keys.has("Right GUI") ? 0x0800 : 0);
  }

  function recordKey(key, down, repeated = false, extraMods = 0) {
    if (!opened || !input.focused || !key) return false;
    const { name, scancode, keycode } = key;
    const held = input.keysDown.has(name);
    if (down && !held) {
      input.keysDown.add(name);
      input.keysPressed.add(name);
    } else if (!down && held) {
      input.keysDown.delete(name);
      input.keysReleased.add(name);
    } else if (!repeated || !down) {
      return true;
    }
    input.events.push({
      kind: down ? 1 : 2, name, scancode, keycode, mods: modifiers() | extraMods, repeat: repeated,
    });
    return true;
  }

  function injectKey(name, down) {
    return recordKey(keyNames.get(String(name).toLowerCase()), Boolean(down));
  }

  function recordText(text, reportEvents) {
    if (!opened || !input.focused) return false;
    input.text += text;
    if (reportEvents) {
      for (const character of text) {
        const codepoint = character.codePointAt(0);
        input.events.push({ kind: 3, keycode: codepoint, codepoint, text: character });
      }
    }
    return true;
  }

  function injectText(text) {
    return recordText(text, true);
  }

  function recordMotion(x, y, dx, dy, inWindow) {
    input.x = x;
    input.y = y;
    input.inWindow = inWindow;
    input.dx += dx;
    input.dy += dy;
    if (dx || dy) input.events.push({ kind: 4, x, y, dx, dy });
  }

  function recordButton(button, down, clicks) {
    if (!button || input.mouseDown.has(button) === down) return;
    if (down) {
      input.mouseDown.add(button);
      input.mousePressed.add(button);
    } else {
      input.mouseDown.delete(button);
      input.mouseReleased.add(button);
    }
    input.events.push({ kind: down ? 5 : 6, button, clicks, x: input.x, y: input.y });
  }

  function injectMouse(x, y, button = 0, down = false) {
    button = Number(button);
    if (!opened || !input.focused || !Number.isInteger(button) || button < 0 || button > 5) return false;
    const over = x >= 0 && y >= 0 && x < width && y < height;
    recordMotion(x, y, x - input.x, y - input.y, over);
    recordButton(button, Boolean(down), 1);
    return true;
  }

  function clearRelativeMotion() {
    input.dx = input.dy = 0;
    input.events = input.events.filter((event) => event.kind !== 4);
    snapshot.dx = snapshot.dy = 0;
  }

  function tryPointerLock() {
    if (lockPending || locked || !relativeWanted || !canvas?.requestPointerLock) return;
    lockPending = true;
    const generation = pointerLockGeneration;
    function onError(error) {
      if (generation !== pointerLockGeneration) return;
      lockPending = false;
      fail(error?.message || "Pointer lock requires a canvas click");
    }
    try {
      const request = canvas.requestPointerLock();
      request?.catch(onError);
    } catch (error) {
      onError(error);
    }
  }

  function setMouseRelative(on) {
    on = Boolean(on);
    if (!opened || (on && !input.focused)) return fail("The graphics window is not focused");
    if (on === relativeWanted) return 1;
    if (!headless && on && !canvas?.requestPointerLock) return fail("Pointer lock is unavailable");
    relativeWanted = on;
    clearRelativeMotion();
    if (headless) locked = on;
    else if (on) {
      if (window?.navigator.userActivation?.isActive !== false) tryPointerLock();
    } else {
      lockPending = false;
      pointerLockGeneration++;
      if (document?.pointerLockElement === canvas) document.exitPointerLock?.();
      locked = false;
    }
    return 1;
  }

  function injectFocus(focused) {
    focused = Boolean(focused);
    if (!opened || input.focused === focused) return opened;
    if (!focused) {
      for (const name of input.keysDown) injectKey(name, false);
      for (const button of input.mouseDown) recordButton(button, false, 0);
      if (relativeWanted) setMouseRelative(false);
      input.dx = input.dy = input.wheelX = input.wheelY = 0;
    }
    input.focused = focused;
    input.events.push({ kind: focused ? 8 : 9 });
    return true;
  }

  function listen(target, type, handler, options) {
    if (!target) return;
    target.addEventListener(type, handler, options);
    listeners.push(() => target.removeEventListener(type, handler, options));
  }

  function setupInput() {
    if (!canvas) return;
    if (canvas.tabIndex < 0) canvas.tabIndex = 0;
    canvas.focus?.({ preventScroll: true });

    const browserButton = (event) => [1, 2, 3, 4, 5][event.button];
    function motion(event, over, moved = false) {
      if (!input.focused) return;
      const rect = canvas.getBoundingClientRect();
      const xScale = width / (rect.width || width);
      const yScale = height / (rect.height || height);
      if (locked) {
        if (moved) recordMotion(input.x, input.y, (event.movementX || 0) * xScale, (event.movementY || 0) * yScale, true);
      } else {
        const x = (event.clientX - rect.left) * xScale;
        const y = (event.clientY - rect.top) * yScale;
        recordMotion(x, y, x - input.x, y - input.y, over);
      }
    }
    listen(canvas, "focus", () => injectFocus(true));
    listen(canvas, "blur", () => injectFocus(false));
    listen(window, "blur", () => injectFocus(false));
    listen(window, "focus", () => {
      if (document?.activeElement === canvas) injectFocus(true);
    });
    listen(canvas, "mouseenter", (event) => motion(event, true));
    listen(canvas, "mouseleave", (event) => motion(event, false));
    listen(window ?? canvas, "mousemove", (event) => {
      const over = event.target === canvas;
      if (over || locked || input.mouseDown.size) motion(event, over, true);
    });
    listen(canvas, "mousedown", (event) => {
      canvas.focus?.({ preventScroll: true });
      injectFocus(true);
      motion(event, true);
      recordButton(browserButton(event), true, event.detail || 1);
      tryPointerLock();
    });
    listen(window ?? canvas, "mouseup", (event) => {
      const over = event.target === canvas;
      if (over || locked || input.mouseDown.size) motion(event, over);
      recordButton(browserButton(event), false, event.detail || 1);
    });
    listen(canvas, "contextmenu", (event) => event.preventDefault());
    listen(canvas, "wheel", (event) => {
      if (!input.focused) return;
      const units = event.deltaMode === 1 ? 1 / 3 : event.deltaMode === 2 ? 1 : 1 / 100;
      const wheelX = -event.deltaX * units;
      const wheelY = -event.deltaY * units;
      input.wheelX += wheelX;
      input.wheelY += wheelY;
      input.events.push({ kind: 7, x: input.x, y: input.y, wheel_x: wheelX, wheel_y: wheelY });
      event.preventDefault();
    }, { passive: false });

    function keyboard(event) {
      if (!input.focused) return;
      const code = event.code || event.key;
      const key = browserKeys.get(code) ?? browserKeys.get(event.key) ??
        keyNames.get(event.key === " " ? "space" : event.key?.toLowerCase());
      const down = event.type === "keydown";
      const extraMods = (event.getModifierState?.("NumLock") ? 0x1000 : 0) |
        (event.getModifierState?.("CapsLock") ? 0x2000 : 0) |
        (event.getModifierState?.("AltGraph") ? 0x4000 : 0);
      recordKey(key, down, event.repeat, extraMods);
      // The UI snapshot carries text even when the Goose EVENT_TEXT stream is off.
      if (down && !event.isComposing && !event.metaKey &&
          ((!event.ctrlKey && !event.altKey) || (extraMods & 0x4000)) &&
          event.key && Array.from(event.key).length === 1) {
        recordText(event.key, textInput);
      }
      if (["Space", "Left", "Right", "Up", "Down", "Tab", "F5", "F9", "F12"].includes(key?.name)) {
        event.preventDefault();
      }
      if (down && !event.repeat) tryPointerLock();
    }
    listen(canvas, "keydown", keyboard);
    listen(canvas, "keyup", keyboard);
    listen(canvas, "compositionend", (event) => {
      recordText(event.data, textInput);
    });
    listen(canvas, "copy", (event) => {
      if (!input.focused || !event.clipboardData) return;
      event.clipboardData.setData("text/plain", clipboard);
      event.preventDefault();
    });
    listen(canvas, "paste", (event) => {
      if (!input.focused || !event.clipboardData) return;
      clipboard = event.clipboardData.getData("text/plain");
      recordText(clipboard, textInput);
      event.preventDefault();
    });
    listen(document, "pointerlockchange", () => {
      lockPending = false;
      const wasLocked = locked;
      locked = document.pointerLockElement === canvas;
      if (locked && !relativeWanted) {
        document.exitPointerLock?.();
        locked = false;
      }
      if (wasLocked !== locked) clearRelativeMotion();
      if (wasLocked && !locked) {
        relativeWanted = false;
        // The browser can consume Escape when it exits pointer lock.
        if (!input.keysPressed.has("Escape")) {
          injectKey("Escape", true);
          injectKey("Escape", false);
        }
      }
    });
    listen(document, "pointerlockerror", () => {
      if (!lockPending) return;
      lockPending = false;
      fail("Pointer lock requires a canvas click");
    });
    listen(canvas, "webglcontextlost", () => {
      fail("WebGL2 context lost");
      stop();
    });
  }

  function resize(newWidth, newHeight) {
    if (newWidth === width && newHeight === height) return;
    width = newWidth;
    height = newHeight;
    if (gl) {
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== height) canvas.height = height;
    } else {
      screenPixels = new Uint8Array(width * height * 4);
    }
  }

  function updateCanvasSize() {
    if (!gl || !(flags & 1)) return;
    const rect = canvas.getBoundingClientRect?.();
    if (!rect?.width || !rect?.height) return;
    density = window?.devicePixelRatio || 1;
    resize(Math.max(1, Math.round(rect.width * density)), Math.max(1, Math.round(rect.height * density)));
  }

  function setTitle(title) {
    options.onTitle?.(title);
    if (!headless && document && !options.onTitle) document.title = title;
  }

  function open(title, requestedWidth, requestedHeight, requestedFlags, forceHeadless) {
    close();
    lastError = "";
    const w = Number(requestedWidth);
    const h = Number(requestedHeight);
    if (!Number.isSafeInteger(w) || !Number.isSafeInteger(h) || w < 1 || h < 1 || w > 32768 || h > 32768) {
      return fail("Invalid screen dimensions");
    }
    flags = Number(requestedFlags);
    headless = Boolean(forceHeadless || !canvas);
    try {
      gl = headless ? null : canvas.getContext("webgl2", {
        preserveDrawingBuffer: true, antialias: true, alpha: false,
      });
      if (!headless && !gl) return fail("WebGL2 is unavailable");
      opened = true;
      stopped = quitting = false;
      elapsed = dt = frameCount = 0;
      start = previous = now();
      density = headless ? 1 : window?.devicePixelRatio || 1;
      input = freshInput(true);
      snapshot = input;
      textInput = false;
      if (gl) {
        passFramebuffer = gl.createFramebuffer();
        readFramebuffer = gl.createFramebuffer();
        emptyVao = gl.createVertexArray();
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.pixelStorei(gl.PACK_ALIGNMENT, 1);
      }
      resize(Math.round(w * density), Math.round(h * density));
      if (gl && canvas.style && density !== 1) {
        const rect = canvas.getBoundingClientRect();
        if (!canvas.style.width && rect.width === width) canvas.style.width = `${w}px`;
        if (!canvas.style.height && rect.height === height) canvas.style.height = `${h}px`;
      }
      updateCanvasSize();
      setTitle(title);
      if (!headless) setupInput();
      return 1;
    } catch (error) {
      close();
      return fail(error.message);
    }
  }

  function stop() {
    stopped = true;
    if (pendingFrame) {
      const { cancel, resolve } = pendingFrame;
      pendingFrame = null;
      cancel();
      resolve(0);
    }
  }

  function close() {
    stop();
    if (relativeWanted || locked) setMouseRelative(false);
    for (const remove of listeners.splice(0)) remove();
    if (gl) {
      gl.bindVertexArray(null);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.useProgram(null);
      for (const { object } of buffers.values()) gl.deleteBuffer(object);
      for (const { object } of textures.values()) gl.deleteTexture(object);
      for (const { object } of samplers.values()) gl.deleteSampler(object);
      for (const { object, vao } of pipelines.values()) {
        gl.deleteProgram(object);
        gl.deleteVertexArray(vao);
      }
      for (const { object } of uniformBuffers.values()) gl.deleteBuffer(object);
      gl.deleteFramebuffer(passFramebuffer);
      gl.deleteFramebuffer(readFramebuffer);
      gl.deleteVertexArray(emptyVao);
      if (overlay) {
        gl.deleteTexture(overlay.texture);
        gl.deleteProgram(overlay.program);
      }
    }
    for (const resources of [buffers, textures, samplers, pipelines, uniformBuffers]) resources.clear();
    pass = pipeline = indexBinding = overlay = screenPixels = null;
    passFramebuffer = readFramebuffer = emptyVao = null;
    vertexBindings.fill(null);
    targetBindings.clear();
    opened = relativeWanted = locked = lockPending = false;
    pointerLockGeneration++;
    width = height = 0;
    gl = null;
    input = freshInput();
    snapshot = input;
  }

  function snapshotInputForUi() {
    return {
      ...snapshot,
      keysDown: new Set(snapshot.keysDown),
      keysPressed: new Set(snapshot.keysPressed),
      keysReleased: new Set(snapshot.keysReleased),
      mouseDown: new Set(snapshot.mouseDown),
      mousePressed: new Set(snapshot.mousePressed),
      mouseReleased: new Set(snapshot.mouseReleased),
      events: snapshot.events.map((event) => ({ ...event })),
    };
  }

  function canFrame() {
    return opened && !stopped && !quitting && frameCount < (options.maxFrames ?? Infinity);
  }

  function advanceFrame(timestamp) {
    if (!canFrame()) return 0;
    updateCanvasSize();
    dt = Math.max(0, timestamp - previous) / 1000;
    elapsed = Math.max(0, timestamp - start) / 1000;
    previous = timestamp;
    frameCount++;
    snapshot = { ...input, keysDown: new Set(input.keysDown), mouseDown: new Set(input.mouseDown) };
    input.keysPressed = new Set();
    input.keysReleased = new Set();
    input.mousePressed = new Set();
    input.mouseReleased = new Set();
    input.events = [];
    input.text = "";
    input.dx = input.dy = input.wheelX = input.wheelY = 0;
    options.onFrame?.({ frameCount, time: elapsed, deltaTime: dt, width, height });
    return 1;
  }

  function frame() {
    if (!options.asyncFrame) return advanceFrame(now());
    if (!canFrame()) return Promise.resolve(0);
    return new Promise((resolve, reject) => {
      const callback = (timestamp) => {
        pendingFrame = null;
        try { resolve(advanceFrame(timestamp)); } catch (error) { reject(error); }
      };
      const raf = window?.requestAnimationFrame?.bind(window) ?? globalThis.requestAnimationFrame;
      const cancelRaf = window?.cancelAnimationFrame?.bind(window) ?? globalThis.cancelAnimationFrame;
      if (raf) {
        const id = raf(callback);
        pendingFrame = { resolve, cancel: () => cancelRaf?.(id) };
      } else {
        const id = setTimeout(() => callback(now()), 1000 / 60);
        pendingFrame = { resolve, cancel: () => clearTimeout(id) };
      }
    });
  }

  function createBuffer(usage, size, data) {
    if (!opened || !Number.isSafeInteger(size) || size < data.length || size > 0x7fffffff) {
      return fail("Invalid buffer size");
    }
    const index = (usage & 2) !== 0;
    let object = null;
    if (gl) {
      object = gl.createBuffer();
      if (!object) return fail("Could not allocate a buffer");
      const target = index ? gl.ELEMENT_ARRAY_BUFFER : gl.ARRAY_BUFFER;
      if (index) gl.bindVertexArray(emptyVao);
      gl.bindBuffer(target, object);
      if (data.length === size) gl.bufferData(target, data, gl.DYNAMIC_DRAW);
      else {
        gl.bufferData(target, size, gl.DYNAMIC_DRAW);
        if (data.length) gl.bufferSubData(target, 0, data);
      }
      gl.bindBuffer(target, null);
    }
    return storeResource(buffers, { object, size, index });
  }

  function updateBuffer(id, offset, data) {
    const buffer = handle(buffers, id);
    if (!buffer || !Number.isSafeInteger(offset) || offset < 0 || offset > buffer.size - data.length) {
      return fail("Buffer update is out of bounds");
    }
    if (gl && data.length) {
      gl.bindBuffer(gl.COPY_WRITE_BUFFER, buffer.object);
      gl.bufferSubData(gl.COPY_WRITE_BUFFER, offset, data);
    }
    return 1;
  }

  function createTexture(w, h, format, usage) {
    if (!opened || !Number.isSafeInteger(w) || !Number.isSafeInteger(h) || w < 1 || h < 1) {
      return fail("Invalid texture dimensions");
    }
    const depth = format === 18 || format === 20;
    if (!depth && format !== 1 && format !== 2) return fail("Unsupported texture format");
    const limit = gl ? gl.getParameter(gl.MAX_TEXTURE_SIZE) : 16384;
    if (w > limit || h > limit) return fail("Texture dimensions exceed the device limit");
    if ((depth && (usage & 2)) || (!depth && (usage & 4))) return fail("Invalid texture usage for its format");
    let object = null;
    let pixels = null;
    let depths = null;
    if (gl) {
      object = gl.createTexture();
      if (!object) return fail("Could not allocate a texture");
      gl.bindTexture(gl.TEXTURE_2D, object);
      gl.texStorage2D(gl.TEXTURE_2D, 1, depth ? gl.DEPTH_COMPONENT32F : gl.RGBA8, w, h);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    } else {
      try {
        if (depth) depths = new Float32Array(w * h);
        else pixels = new Uint8Array(w * h * 4);
      } catch {
        return fail("Could not allocate a texture");
      }
    }
    return storeResource(textures, { object, width: w, height: h, format, usage, depth, pixels, depths });
  }

  function swapRedBlue(bytes) {
    const result = bytes.slice();
    for (let i = 0; i < bytes.length; i += 4) {
      result[i] = bytes[i + 2];
      result[i + 2] = bytes[i];
    }
    return result;
  }

  function updateTexture(id, data) {
    const texture = handle(textures, id);
    if (!texture || texture.depth || data.length !== texture.width * texture.height * 4) {
      return fail("Texture update must supply all pixels of a color texture");
    }
    const bytes = texture.format === 2 ? swapRedBlue(data) : data;
    if (gl) {
      gl.bindTexture(gl.TEXTURE_2D, texture.object);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, texture.width, texture.height, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
    } else {
      texture.pixels.set(bytes);
    }
    return 1;
  }

  function compareFunc(compare) {
    return [gl.ALWAYS, gl.NEVER, gl.LESS, gl.EQUAL, gl.LEQUAL,
      gl.GREATER, gl.NOTEQUAL, gl.GEQUAL, gl.ALWAYS][compare];
  }

  function createSampler(filter, wrap, compare) {
    if (!opened || ![0, 1].includes(filter) || ![0, 1, 2].includes(wrap) || compare < 0 || compare > 8) {
      return fail("Invalid sampler settings");
    }
    let object = null;
    if (gl) {
      object = gl.createSampler();
      if (!object) return fail("Could not allocate a sampler");
      const sampling = filter ? gl.LINEAR : gl.NEAREST;
      const addressing = [gl.REPEAT, gl.MIRRORED_REPEAT, gl.CLAMP_TO_EDGE][wrap];
      gl.samplerParameteri(object, gl.TEXTURE_MIN_FILTER, sampling);
      gl.samplerParameteri(object, gl.TEXTURE_MAG_FILTER, sampling);
      gl.samplerParameteri(object, gl.TEXTURE_WRAP_S, addressing);
      gl.samplerParameteri(object, gl.TEXTURE_WRAP_T, addressing);
      if (compare) {
        gl.samplerParameteri(object, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
        gl.samplerParameteri(object, gl.TEXTURE_COMPARE_FUNC, compareFunc(compare));
      }
    }
    return storeResource(samplers, { object });
  }

  function createPipeline(vs, fs, formats, primitive, cull, clockwise, wireframe,
    depthTest, depthWrite, depthCompare, blend, instanceLocation, depthBias, depthBiasSlope) {
    if (!opened) return fail("Graphics is closed");
    if (primitive < 0 || primitive > 4 || cull < 0 || cull > 2 ||
        depthCompare < 0 || depthCompare > 8 || blend < 0 || blend > 4) {
      return fail("Invalid graphics pipeline state");
    }
    if (wireframe) return fail("WebGL2 does not support polygon wireframe mode");

    let object = null;
    let vao = null;
    try {
      const vertex = transpileShader(vs, "vert");
      const fragment = transpileShader(fs, "frag");
      const { layout, strides } = vertexLayout(vertex.attributes, formats, instanceLocation);
      const blocks = new Map();
      const resources = [];
      let flipLocation = null;
      if (gl) {
        object = linkProgram(gl, vertex.source, fragment.source);
        vao = gl.createVertexArray();
        if (!vao) throw new Error("Could not allocate a vertex array");
        gl.useProgram(object);
        flipLocation = gl.getUniformLocation(object, "_goose_flip_y");
        const maxBlockBindings = gl.getParameter(gl.MAX_UNIFORM_BUFFER_BINDINGS);
        for (const { name, point } of [...vertex.blocks, ...fragment.blocks]) {
          const index = gl.getUniformBlockIndex(object, name);
          if (index === gl.INVALID_INDEX) continue;
          if (point >= maxBlockBindings) throw new Error(`Uniform binding ${point} exceeds the device limit`);
          const size = gl.getActiveUniformBlockParameter(object, index, gl.UNIFORM_BLOCK_DATA_SIZE);
          gl.uniformBlockBinding(object, index, point);
          blocks.set(point, size);
        }
        const maxUnits = gl.getParameter(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS);
        for (const binding of [...vertex.samplers, ...fragment.samplers]) {
          const location = gl.getUniformLocation(object, binding.name);
          if (location === null) continue;
          const unit = resources.length;
          if (unit >= maxUnits) throw new Error("Texture bindings exceed the device limit");
          gl.uniform1i(location, unit);
          resources.push({ ...binding, unit });
        }
        // Optimized-out declarations still contribute to the packed stride.
        const active = new Set();
        const count = gl.getProgramParameter(object, gl.ACTIVE_ATTRIBUTES);
        for (let i = 0; i < count; i++) {
          const info = gl.getActiveAttrib(object, i);
          active.add(gl.getAttribLocation(object, info.name));
        }
        for (const attribute of layout) attribute.active = active.has(attribute.location);
        gl.useProgram(pipeline?.object ?? null);
      } else {
        resources.push(...vertex.samplers, ...fragment.samplers);
      }
      return storeResource(pipelines, {
        object, vao, flipLocation, blocks, resources, layout, strides, primitive,
        cull, clockwise: Boolean(clockwise), depthTest, depthWrite, depthCompare, blend, depthBias, depthBiasSlope,
      });
    } catch (error) {
      if (gl && object) {
        gl.useProgram(pipeline?.object ?? null);
        gl.deleteProgram(object);
      }
      if (gl && vao) gl.deleteVertexArray(vao);
      return fail(error.message);
    }
  }

  function colorBytes(color) {
    return Uint8Array.from(color, (value) => Math.round(Math.min(1, Math.max(0, value)) * 255));
  }

  function clearPixels(pixels, color) {
    const rgba = colorBytes(color);
    new Uint32Array(pixels.buffer, pixels.byteOffset, pixels.byteLength / 4)
      .fill(new Uint32Array(rgba.buffer)[0]);
  }

  function beginPass(colorIds, resolveIds, depthId, layer, mip, clearColor, clearDepth, color, depthValue) {
    if (!opened || pass) return fail("Cannot begin a render pass");
    if (layer || mip || resolveIds.some(Boolean)) return fail("WebGL textures use one layer, level and sample");
    const screen = colorIds[0] === SCREEN || depthId === SCREEN_DEPTH;
    if (screen && (colorIds.slice(1).some(Boolean) || (colorIds[0] && colorIds[0] !== SCREEN) ||
        (depthId && depthId !== SCREEN_DEPTH))) {
      return fail("Screen attachments must belong to the screen framebuffer");
    }
    const colors = [];
    let depth = null;
    let targetWidth = width;
    let targetHeight = height;
    if (!screen) {
      for (const id of colorIds) {
        const texture = handle(textures, id);
        if (id && !(texture?.usage & 2)) return fail("Invalid color attachment");
        colors.push(texture ?? null);
      }
      depth = handle(textures, depthId);
      if (depthId && !(depth?.usage & 4)) return fail("Invalid depth attachment");
      const first = colors.find(Boolean) ?? depth;
      if (!first) return fail("A render pass needs an attachment");
      if ([...colors, depth].some((texture) => texture &&
          (texture.width !== first.width || texture.height !== first.height))) {
        return fail("Render pass attachments must have the same dimensions");
      }
      targetWidth = first.width;
      targetHeight = first.height;
    }
    const hasColor = screen ? Boolean(colorIds[0]) : colors.some(Boolean);
    if (gl) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, screen ? null : passFramebuffer);
      if (screen) gl.drawBuffers([hasColor ? gl.BACK : gl.NONE]);
      else {
        const drawBuffers = colors.map((texture, i) => {
          const attachment = gl.COLOR_ATTACHMENT0 + i;
          gl.framebufferTexture2D(gl.FRAMEBUFFER, attachment, gl.TEXTURE_2D, texture?.object ?? null, 0);
          return texture ? attachment : gl.NONE;
        });
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depth?.object ?? null, 0);
        gl.drawBuffers(drawBuffers);
        gl.readBuffer(drawBuffers.find((attachment) => attachment !== gl.NONE) ?? gl.NONE);
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
          gl.bindFramebuffer(gl.FRAMEBUFFER, null);
          return fail("Incomplete render framebuffer");
        }
      }
      gl.viewport(0, 0, targetWidth, targetHeight);
      gl.disable(gl.SCISSOR_TEST);
      let mask = 0;
      if (hasColor && clearColor) {
        gl.colorMask(true, true, true, true);
        gl.clearColor(...color);
        mask |= gl.COLOR_BUFFER_BIT;
      }
      if (depthId && clearDepth) {
        gl.depthMask(true);
        gl.clearDepth(depthValue);
        mask |= gl.DEPTH_BUFFER_BIT;
      }
      if (mask) gl.clear(mask);
    } else {
      if (clearColor) {
        if (screen && hasColor) clearPixels(screenPixels, color);
        for (const texture of colors) if (texture) clearPixels(texture.pixels, color);
      }
      if (clearDepth) depth?.depths.fill(depthValue);
    }
    pass = { screen, hasColor, hasDepth: Boolean(depthId), width: targetWidth, height: targetHeight, draws: 0 };
    pipeline = indexBinding = null;
    vertexBindings.fill(null);
    targetBindings.clear();
    verticesDirty = true;
    return 1;
  }

  function endPass() {
    if (!pass) return;
    pass = pipeline = null;
    if (gl) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.drawBuffers([gl.BACK]);
      gl.disable(gl.SCISSOR_TEST);
    }
  }

  function toggle(capability, enabled) {
    if (enabled) gl.enable(capability);
    else gl.disable(capability);
  }

  function bindPipeline(id) {
    const next = handle(pipelines, id);
    if (!pass || !next) {
      pipeline = null;
      return fail("Cannot bind a graphics pipeline");
    }
    pipeline = next;
    verticesDirty = true;
    if (!gl) return;
    gl.useProgram(next.object);
    gl.uniform1f(next.flipLocation, pass.screen ? 1 : -1);
    toggle(gl.CULL_FACE, next.cull);
    if (next.cull) gl.cullFace(next.cull === 1 ? gl.FRONT : gl.BACK);
    gl.frontFace(next.clockwise !== !pass.screen ? gl.CW : gl.CCW);
    toggle(gl.DEPTH_TEST, pass.hasDepth && (next.depthTest || next.depthWrite));
    gl.depthMask(Boolean(pass.hasDepth && next.depthWrite));
    gl.depthFunc(next.depthTest ? compareFunc(next.depthCompare) : gl.ALWAYS);
    const bias = next.depthBias || next.depthBiasSlope;
    toggle(gl.POLYGON_OFFSET_FILL, bias);
    if (bias) gl.polygonOffset(next.depthBiasSlope, next.depthBias);
    toggle(gl.BLEND, next.blend);
    if (next.blend) {
      const factors = [
        null,
        [gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA],
        [gl.SRC_ALPHA, gl.ONE, gl.ONE, gl.ONE],
        [gl.ONE, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA],
        [gl.DST_COLOR, gl.ZERO, gl.ZERO, gl.ONE],
      ];
      gl.blendEquation(gl.FUNC_ADD);
      gl.blendFuncSeparate(...factors[next.blend]);
    }
  }

  function bindVertex(slot, id, offset) {
    const buffer = handle(buffers, id);
    if (!pass || ![0, 1].includes(slot) || !buffer || buffer.index || offset < 0 || offset > buffer.size) {
      return fail("Invalid vertex buffer binding");
    }
    vertexBindings[slot] = { buffer, offset };
    verticesDirty = true;
  }

  function bindIndex(id, size, offset) {
    const buffer = handle(buffers, id);
    if (!pass || !buffer?.index || ![2, 4].includes(size) || offset < 0 ||
        offset > buffer.size || offset % size) {
      return fail("Invalid index buffer binding");
    }
    indexBinding = { buffer, size, offset };
    verticesDirty = true;
  }

  function bindTexture(stage, slot, textureId, samplerId) {
    const texture = handle(textures, textureId);
    const sampler = handle(samplers, samplerId);
    if (!pass || !texture || !sampler || !(texture.usage & 1)) return fail("Invalid sampled texture binding");
    targetBindings.set(stage * 8 + slot, { texture, sampler });
  }

  function pushUniforms(stage, slot, bytes) {
    if (!pass || !pipeline) return fail("Uniforms require a bound pipeline");
    if (!gl) return;
    const point = stage * 8 + slot;
    const size = pipeline.blocks.get(point);
    if (size === undefined) return; // The linker can eliminate a whole block.
    if (bytes.length !== size) return fail(`Uniform slot ${slot} expects ${size} bytes, got ${bytes.length}`);
    let buffer = uniformBuffers.get(point);
    if (!buffer) {
      const object = gl.createBuffer();
      if (!object) return fail("Could not allocate a uniform buffer");
      buffer = { object, size: 0, pipeline: null };
      uniformBuffers.set(point, buffer);
    }
    gl.bindBuffer(gl.UNIFORM_BUFFER, buffer.object);
    if (buffer.size !== size) {
      gl.bufferData(gl.UNIFORM_BUFFER, bytes, gl.DYNAMIC_DRAW);
      buffer.size = size;
    } else {
      gl.bufferSubData(gl.UNIFORM_BUFFER, 0, bytes);
    }
    buffer.pipeline = pipeline;
    gl.bindBufferBase(gl.UNIFORM_BUFFER, point, buffer.object);
  }

  function draw(count, instances, indexed) {
    if (!pass || !pipeline) return fail("The draw needs a bound graphics pipeline");
    if (!Number.isSafeInteger(count) || !Number.isSafeInteger(instances) || count < 0 || instances < 0 ||
        count > 0x7fffffff || instances > 0x7fffffff) return fail("Invalid draw count");
    if (!count || !instances) return;
    if (indexed && (!indexBinding || indexBinding.offset + count * indexBinding.size > indexBinding.buffer.size)) {
      return fail("Indexed draw is out of bounds");
    }
    for (const { location, slot, active } of pipeline.layout) {
      if (active !== false && !vertexBindings[slot]) return fail(`Missing vertex buffer for location ${location}`);
    }
    for (const { stage, slot, unit } of pipeline.resources) {
      const binding = targetBindings.get(stage * 8 + slot);
      if (!binding) return fail(`Missing sampled texture at slot ${slot}`);
      if (gl) {
        gl.activeTexture(gl.TEXTURE0 + unit);
        gl.bindTexture(gl.TEXTURE_2D, binding.texture.object);
        gl.bindSampler(unit, binding.sampler.object);
      }
    }
    pass.draws++;
    if (!gl) return;
    for (const point of pipeline.blocks.keys()) {
      if (uniformBuffers.get(point)?.pipeline !== pipeline) return fail(`Missing uniforms at binding ${point}`);
    }
    if (verticesDirty) {
      const vao = pipeline.layout.length || indexed ? pipeline.vao : emptyVao;
      gl.bindVertexArray(vao);
      if (vao === pipeline.vao) {
        for (const attribute of pipeline.layout) {
          const { location, slot, count, type, offset, normalized, integer, active } = attribute;
          if (!active) continue;
          const binding = vertexBindings[slot];
          gl.bindBuffer(gl.ARRAY_BUFFER, binding.buffer.object);
          gl.enableVertexAttribArray(location);
          const stride = pipeline.strides[slot];
          const pointer = binding.offset + offset;
          if (integer) gl.vertexAttribIPointer(location, count, type, stride, pointer);
          else gl.vertexAttribPointer(location, count, type, normalized, stride, pointer);
          gl.vertexAttribDivisor(location, slot);
        }
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBinding?.buffer.object ?? null);
      }
      verticesDirty = false;
    }
    const mode = [gl.TRIANGLES, gl.TRIANGLE_STRIP, gl.LINES, gl.LINE_STRIP, gl.POINTS][pipeline.primitive];
    if (indexed) {
      const type = indexBinding.size === 2 ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
      if (instances === 1) gl.drawElements(mode, count, type, indexBinding.offset);
      else gl.drawElementsInstanced(mode, count, type, indexBinding.offset, instances);
    } else if (instances === 1) {
      gl.drawArrays(mode, 0, count);
    } else {
      gl.drawArraysInstanced(mode, 0, count, instances);
    }
  }

  function setRectangle(scissor, x, y, w, h) {
    if (!gl || !pass) return;
    const bottom = pass.screen ? pass.height - Math.trunc(y + h) : Math.trunc(y);
    if (scissor) {
      gl.enable(gl.SCISSOR_TEST);
      gl.scissor(x, bottom, w, h);
    } else {
      gl.viewport(x, bottom, w, h);
    }
  }

  function readPixels(id) {
    if (!opened) return null;
    const screen = id === SCREEN;
    const texture = screen ? null : handle(textures, id);
    if (!screen && (!texture || texture.depth)) {
      fail("Readback requires a color texture");
      return null;
    }
    let bytes;
    if (!gl) {
      bytes = screen ? screenPixels.slice() : texture.pixels.slice();
    } else {
      const w = screen ? width : texture.width;
      const h = screen ? height : texture.height;
      const rowBytes = w * 4;
      bytes = new Uint8Array(rowBytes * h);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, screen ? null : readFramebuffer);
      if (texture) {
        gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture.object, 0);
        gl.readBuffer(gl.COLOR_ATTACHMENT0);
      }
      gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
      if (texture) gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, null, 0);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, pass && !pass.screen ? passFramebuffer : null);
      // Texture uploads and offscreen passes already store the logical top
      // row at texture y=0. Only the default framebuffer has inverted rows.
      if (screen) {
        const row = new Uint8Array(rowBytes);
        for (let y = 0; y < (h >> 1); y++) {
          const top = y * rowBytes;
          const bottom = (h - 1 - y) * rowBytes;
          row.set(bytes.subarray(top, top + rowBytes));
          bytes.copyWithin(top, bottom, bottom + rowBytes);
          bytes.set(row, bottom);
        }
      }
    }
    return texture?.format === 2 ? swapRedBlue(bytes) : bytes;
  }

  function screenshotPngBytes() {
    const pixels = readPixels(SCREEN);
    return pixels ? encodePng(width, height, pixels) : null;
  }

  function screenshot(path) {
    if (!options.fs?.writeFile) return fail("Screenshot requires a filesystem");
    try {
      const bytes = screenshotPngBytes();
      return bytes && options.fs.writeFile(path, bytes) ? 1 : fail("Could not write screenshot");
    } catch (error) {
      return fail(error.message);
    }
  }

  function compositeCanvas2D(overlayCanvas) {
    if (!gl || pass || !overlayCanvas?.width || !overlayCanvas.height) return false;
    if (!overlay) {
      const program = linkProgram(gl, shaderHeader + `
out vec2 uv;
void main() {
    vec2 p = vec2(float(gl_VertexID & 1), float(gl_VertexID >> 1));
    uv = vec2(p.x, 1.0 - p.y);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
`, shaderHeader + `
in vec2 uv;
uniform sampler2D image;
out vec4 result;
void main() { result = texture(image, uv); }
`);
      const texture = gl.createTexture();
      if (!texture) {
        gl.deleteProgram(program);
        return false;
      }
      overlay = { program, texture, width: 0, height: 0 };
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.drawBuffers([gl.BACK]);
    gl.viewport(0, 0, width, height);
    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.CULL_FACE);
    gl.disable(gl.SCISSOR_TEST);
    gl.disable(gl.POLYGON_OFFSET_FILL);
    gl.enable(gl.BLEND);
    gl.blendEquation(gl.FUNC_ADD);
    gl.blendFuncSeparate(gl.ONE, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.useProgram(overlay.program);
    gl.bindVertexArray(emptyVao);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, overlay.texture);
    gl.bindSampler(0, null);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    try {
      if (overlay.width !== overlayCanvas.width || overlay.height !== overlayCanvas.height) {
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, overlayCanvas);
        overlay.width = overlayCanvas.width;
        overlay.height = overlayCanvas.height;
      } else {
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, gl.RGBA, gl.UNSIGNED_BYTE, overlayCanvas);
      }
    } finally {
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    }
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    return true;
  }

  function writeFloatPair(ptr, x, y) {
    const at = mem.address(ptr);
    const view = mem.view();
    view.setFloat32(at, x, true);
    view.setFloat32(at + 4, y, true);
  }

  function writeEvent(index, ptr) {
    const event = snapshot.events[Number(index)];
    if (!event) return;
    const at = mem.address(ptr);
    const view = mem.view();
    const integerFields = ["kind", "scancode", "keycode", "mods", "button", "clicks"];
    const floatFields = ["x", "y", "dx", "dy", "wheel_x", "wheel_y"];
    integerFields.forEach((name, i) => view.setInt32(at + i * 4, event[name] ?? 0, true));
    floatFields.forEach((name, i) => view.setFloat32(at + (integerFields.length + i) * 4, event[name] ?? 0, true));
  }

  function setClipboard(value) {
    clipboard = value;
    try {
      window?.navigator.clipboard?.writeText(value)?.catch(() => {});
    } catch {
      // The in-app clipboard remains available when browser access fails.
    }
    return 1;
  }

  const imports = {
    gs_gfx_open: (...args) => {
      const { view, next } = mem.readSliceView(args);
      return open(decoder.decode(view), ...args.slice(next));
    },
    gs_gfx_close: close,
    gs_gfx_frame: frame,
    gs_gfx_quit: () => { quitting = true; },
    gs_gfx_flush: () => { gl?.finish(); },
    gs_gfx_error: (out) => mem.appendBuilder(out, lastError),
    gs_gfx_driver: (out) => mem.appendBuilder(out, gl ? "webgl2" : "headless"),
    gs_gfx_set_title: (...args) => setTitle(decoder.decode(mem.readSliceView(args).view)),
    gs_gfx_screen: () => opened ? SCREEN : 0,
    gs_gfx_screen_depth: () => opened ? SCREEN_DEPTH : 0,
    gs_gfx_screen_size: (out) => {
      mem.writeI32(out, width);
      mem.writeI32(mem.address(out) + 4, height);
    },
    gs_gfx_pixel_density: () => density,
    gs_gfx_display_scale: () => density,
    gs_gfx_time: () => elapsed,
    gs_gfx_delta_time: () => dt,
    gs_gfx_frame_count: () => BigInt(frameCount),
    gs_gfx_key_down: (...args) => queryKey(args, snapshot.keysDown),
    gs_gfx_key_pressed: (...args) => queryKey(args, snapshot.keysPressed),
    gs_gfx_key_released: (...args) => queryKey(args, snapshot.keysReleased),
    gs_gfx_mouse_down: (button) => snapshot.mouseDown.has(Number(button)),
    gs_gfx_mouse_pressed: (button) => snapshot.mousePressed.has(Number(button)),
    gs_gfx_mouse_released: (button) => snapshot.mouseReleased.has(Number(button)),
    gs_gfx_mouse_pos: (ptr) => writeFloatPair(ptr, snapshot.x, snapshot.y),
    gs_gfx_mouse_delta: (ptr) => writeFloatPair(ptr, snapshot.dx, snapshot.dy),
    gs_gfx_mouse_wheel: () => snapshot.wheelY,
    gs_gfx_mouse_in_window: () => snapshot.inWindow || snapshot.mouseDown.size > 0,
    gs_gfx_focused: () => snapshot.focused,
    gs_gfx_set_mouse_relative: setMouseRelative,
    gs_gfx_mouse_relative: () => locked,
    gs_gfx_event_count: () => BigInt(snapshot.events.length),
    gs_gfx_event_at: writeEvent,
    gs_gfx_text_input: (on) => { textInput = Boolean(on); },
    gs_gfx_clipboard: (out) => mem.appendBuilder(out, clipboard),
    gs_gfx_set_clipboard: (...args) => setClipboard(decoder.decode(mem.readSliceView(args).view)),
    gs_gfx_inject_key: (...args) => {
      const { view, next } = mem.readSliceView(args);
      return injectKey(decoder.decode(view), args[next]);
    },
    gs_gfx_inject_mouse: injectMouse,
    gs_gfx_inject_text: (...args) => injectText(decoder.decode(mem.readSliceView(args).view)),
    gs_gfx_inject_focus: injectFocus,
    gs_gfx_buffer: (usage, size, ...args) => createBuffer(Number(usage), Number(size), mem.readSliceView(args).view),
    gs_gfx_update_buffer: (id, offset, ...args) => updateBuffer(id, Number(offset), mem.readSliceView(args).view),
    gs_gfx_buffer_size: (id) => BigInt(handle(buffers, id)?.size ?? 0),
    gs_gfx_release_buffer: (id) => release(buffers, id, gl?.deleteBuffer),
    gs_gfx_texture2d: (w, h, format, usage) => createTexture(Number(w), Number(h), format, usage),
    gs_gfx_update_texture: (id, ...args) => updateTexture(id, mem.readSliceView(args).view),
    gs_gfx_read_pixels: (id, out) => {
      const bytes = readPixels(id);
      if (bytes) mem.appendBuilder(out, bytes);
    },
    gs_gfx_screenshot: (...args) => screenshot(mem.readSlice(args).bytes),
    gs_gfx_release_texture: (id) => release(textures, id, gl?.deleteTexture),
    gs_gfx_sampler: createSampler,
    gs_gfx_release_sampler: (id) => release(samplers, id, gl?.deleteSampler),
    gs_gfx_pipeline: (...args) => {
      const vs = mem.readSliceView(args);
      const fs = mem.readSliceView(args, vs.next);
      const formats = mem.readSliceView(args, fs.next);
      return createPipeline(vs.view, fs.view, formats.view, ...args.slice(formats.next));
    },
    gs_gfx_release_pipeline: (id) => {
      const resource = handle(pipelines, id);
      if (resource === pipeline) pipeline = null;
      if (gl && resource) gl.deleteVertexArray(resource.vao);
      release(pipelines, id, gl?.deleteProgram);
    },
    gs_gfx_begin_pass: (c0, c1, c2, c3, r0, r1, r2, r3, depth, layer, mip,
      clearColor, clearDepth, r, g, b, a, depthValue) => beginPass(
      [c0, c1, c2, c3], [r0, r1, r2, r3], depth, layer, mip, clearColor, clearDepth, [r, g, b, a], depthValue),
    gs_gfx_end_pass: endPass,
    gs_gfx_bind: bindPipeline,
    gs_gfx_bind_vertex_buffer: (slot, id, offset) => bindVertex(Number(slot), id, Number(offset)),
    gs_gfx_bind_index_buffer: (id, size, offset) => bindIndex(id, Number(size), Number(offset)),
    gs_gfx_bind_texture: (stage, slot, texture, sampler) => bindTexture(Number(stage), Number(slot), texture, sampler),
    gs_gfx_push_uniforms: (stage, slot, ...args) => pushUniforms(Number(stage), Number(slot), mem.readSliceView(args).view),
    gs_gfx_viewport: (x, y, w, h) => setRectangle(false, x, y, w, h),
    gs_gfx_scissor: (x, y, w, h) => setRectangle(true, Number(x), Number(y), Number(w), Number(h)),
    gs_gfx_draw: (count) => draw(Number(count), 1, false),
    gs_gfx_draw_instanced: (count, instances) => draw(Number(count), Number(instances), false),
    gs_gfx_draw_indexed: (count) => draw(Number(count), 1, true),
    gs_gfx_draw_indexed_instanced: (count, instances) => draw(Number(count), Number(instances), true),
  };

  const gfx = {
    stop, close, snapshotInputForUi, compositeCanvas2D, screenshotPngBytes,
    injectKey, injectMouse, injectText, injectFocus,
    get width() { return width; },
    get height() { return height; },
    get gl() { return gl; },
    canvas,
  };
  return { imports, gfx };
}
