// Immediate-mode windows and widgets for the Goose Web host.
const WINDOW = {
  BORDER: 1, MOVABLE: 2, SCALABLE: 4, CLOSABLE: 8, MINIMIZABLE: 16,
  NO_SCROLLBAR: 32, TITLE: 64, SCROLL_AUTO_HIDE: 128, BACKGROUND: 256,
  SCALE_LEFT: 512, NO_INPUT: 1024,
};
const EDIT = {
  READ_ONLY: 1, AUTO_SELECT: 2, SIG_ENTER: 4, ALLOW_TAB: 8, NO_CURSOR: 16,
  SELECTABLE: 32, CLIPBOARD: 64, CTRL_ENTER_NEWLINE: 128, NO_HORIZONTAL_SCROLL: 256,
  MULTILINE: 1024, GOTO_END: 2048,
  ACTIVE: 1, INACTIVE: 2, ACTIVATED: 4, DEACTIVATED: 8, COMMITTED: 16,
};
const COLOR = {
  TEXT: 0, WINDOW: 1, HEADER: 2, BORDER: 3, BUTTON: 4, BUTTON_HOVER: 5, BUTTON_ACTIVE: 6,
  TOGGLE: 7, TOGGLE_HOVER: 8, TOGGLE_CURSOR: 9, SELECT: 10, SELECT_ACTIVE: 11,
  SLIDER: 12, SLIDER_CURSOR: 13, SLIDER_CURSOR_HOVER: 14, SLIDER_CURSOR_ACTIVE: 15,
  PROPERTY: 16, EDIT: 17, EDIT_CURSOR: 18, COMBO: 19,
  SCROLLBAR: 23, SCROLLBAR_CURSOR: 24, SCROLLBAR_CURSOR_HOVER: 25, SCROLLBAR_CURSOR_ACTIVE: 26,
};
const PALETTE = Uint8Array.from([
  [220, 220, 220], [45, 45, 45], [40, 40, 40], [65, 65, 65],
  [50, 50, 50], [65, 63, 62], [78, 76, 75], [50, 50, 50],
  [65, 63, 62], [100, 100, 100], [45, 45, 45], [35, 35, 35],
  [38, 38, 38], [100, 100, 100], [120, 120, 120], [150, 150, 150],
  [38, 38, 38], [38, 38, 38], [175, 175, 175], [45, 45, 45],
  [120, 120, 120], [45, 45, 45], [255, 0, 0], [40, 40, 40],
  [100, 100, 100], [120, 120, 120], [150, 150, 150], [40, 40, 40],
].flatMap(rgb => [...rgb, 255]));
const SYMBOLS = ["", "×", "_", "●", "○", "■", "□", "▲", "▼", "◀", "▶", "+", "−"];
const FILTERS = [null, /^[\x20-\x7e]$/, /^[0-9.+-]$/, /^[0-9-]$/,
  /^[0-9a-f]$/i, /^[0-7]$/, /^[01]$/];
const PAD = 8;
const GAP = 4;
const SCROLL_WIDTH = 8;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { ignoreBOM: true });
let nextFont = 0;

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
const rect = (x, y, w, h) => ({ x, y, w: Math.max(0, w), h: Math.max(0, h) });
const right = r => r.x + r.w;
const bottom = r => r.y + r.h;
const inset = (r, x, y = x) => rect(r.x + x, r.y + y, r.w - 2 * x, r.h - 2 * y);
const hit = (r, p) => r && p.x >= r.x && p.x < right(r) && p.y >= r.y && p.y < bottom(r);
const fraction = (value, size) => size > 0 ? clamp(value / size, 0, 1) : 0;

function cssPalette(bytes) {
  const colors = [];
  for (let i = 0; i < bytes.length; i += 4) {
    colors.push(`rgba(${bytes[i]}, ${bytes[i + 1]}, ${bytes[i + 2]}, ${bytes[i + 3] / 255})`);
  }
  return colors;
}

function fill(g, r, color) {
  g.fillStyle = color;
  g.fillRect(r.x, r.y, r.w, r.h);
}

function box(g, r, color, border, radius = 3) {
  if (!r.w || !r.h) return;
  g.beginPath();
  g.roundRect(r.x, r.y, r.w, r.h, radius);
  g.fillStyle = color;
  g.fill();
  if (border) {
    g.strokeStyle = border;
    g.lineWidth = 1;
    g.stroke();
  }
}

function clip(g, r) {
  g.beginPath();
  g.rect(r.x, r.y, r.w, r.h);
  g.clip();
}

function lettering(g, r, text, color, align = 17) {
  if (!r.w || !r.h) return;
  g.save();
  clip(g, r);
  g.fillStyle = color;
  g.textBaseline = "middle";
  g.textAlign = align === 18 ? "center" : align === 20 ? "right" : "left";
  const x = align === 18 ? r.x + r.w / 2 : align === 20 ? right(r) - 5 : r.x + 5;
  g.fillText(text, x, r.y + r.h / 2);
  g.restore();
}

function rgbToHsv([r, g, b], previousHue) {
  const v = Math.max(r, g, b);
  const chroma = v - Math.min(r, g, b);
  if (!chroma) return [previousHue, 0, v];
  let hue = (g - b) / chroma;
  if (v === g) hue = 2 + (b - r) / chroma;
  if (v === b && v !== r && v !== g) hue = 4 + (r - g) / chroma;
  return [((hue / 6) + 1) % 1, chroma / v, v];
}

function hsvToRgb(h, s, v) {
  return [5, 3, 1].map(offset => {
    const k = (offset + h * 6) % 6;
    return v - v * s * clamp(Math.min(k, 4 - k), 0, 1);
  });
}

function gradient(g, r, vertical, colors) {
  const ramp = g.createLinearGradient(r.x, r.y, vertical ? r.x : right(r), vertical ? bottom(r) : r.y);
  colors.forEach((color, i) => ramp.addColorStop(i / (colors.length - 1), color));
  fill(g, r, ramp);
}

function inputSnapshot(raw, scale) {
  const keys = new Set(raw.keysPressed);
  const held = raw.keysDown;
  for (const event of raw.events ?? []) {
    if (event.kind === 1 && event.repeat) keys.add(event.name);
  }
  const aliases = {
    Enter: ["Return", "Keypad Enter"], ArrowLeft: ["Left"], ArrowRight: ["Right"],
    KeyA: ["A"], KeyC: ["C"], KeyX: ["X"],
  };
  return {
    x: Number(raw.x ?? -Infinity) / scale,
    y: Number(raw.y ?? -Infinity) / scale,
    down: Boolean(raw.mouseDown?.has(1)),
    pressed: Boolean(raw.mousePressed?.has(1)),
    released: Boolean(raw.mouseReleased?.has(1)),
    wheel: Number(raw.wheelY ?? 0),
    text: raw.text ?? "",
    key: name => keys.has(name) || aliases[name]?.some(key => keys.has(key)),
    ctrl: ["Left Ctrl", "Right Ctrl", "Left GUI", "Right GUI"].some(key => held?.has(key)),
    shift: ["Left Shift", "Right Shift"].some(key => held?.has(key)),
  };
}

function region(bounds, commands, innerWidth = bounds.w) {
  return { bounds, commands, x: bounds.x, y: bounds.y, width: innerWidth, row: null };
}

function advanceRow(area) {
  if (area.row?.col > 0) area.y += area.row.height + GAP;
}

function layout(ctx, height, cols, width, sizes, dynamic) {
  const area = ctx.area;
  if (!area) return;
  advanceRow(area);
  area.row = null;
  if (cols < 1) return;
  const available = Math.max(0, area.width - GAP * (cols - 1));
  area.row = { height: Math.max(0, height), col: 0, cols, x: area.x, available, width, sizes, dynamic };
}

function nextBounds(ctx, consume) {
  const area = ctx.area;
  const row = area?.row;
  if (!row) return rect(0, 0, 0, 0);
  const wrapped = row.col === row.cols;
  const col = wrapped ? 0 : row.col;
  const x = wrapped ? area.x : row.x;
  const y = wrapped ? area.y + row.height + GAP : area.y;
  let w = row.sizes?.[col] ?? row.width;
  if (row.dynamic) w = row.available * (w ?? 1 / row.cols);
  const bounds = rect(x, y, w, row.height);
  if (consume) {
    area.y = y;
    row.col = col + 1;
    row.x = right(bounds) + GAP;
  }
  return bounds;
}

function hovered(ctx, bounds) {
  const win = ctx.win;
  if (!win || win.flags & WINDOW.NO_INPUT || ctx.blockClick) return false;
  if (ctx.target !== win && ctx.target !== null) return false;
  if (ctx.menu && !ctx.popup && ctx.menu.key !== ctx.menuTrigger) return false;
  return hit(ctx.area?.bounds, ctx.input) && hit(bounds, ctx.input);
}

function widget(ctx, kind) {
  const bounds = nextBounds(ctx, true);
  const win = ctx.win;
  const index = win ? win.widgetIndex++ : 0;
  const key = JSON.stringify([win?.title, kind, index]);
  return { bounds, key, over: hovered(ctx, bounds) };
}

function interact(ctx, key, over, start) {
  if (over && ctx.input.pressed && !ctx.press) {
    ctx.press = { key, win: ctx.win, x: ctx.input.x, y: ctx.input.y, ...start };
  }
  return ctx.press?.key === key ? ctx.press : null;
}

function clicked(ctx, key, over) {
  return Boolean(interact(ctx, key, over) && over && ctx.input.released);
}

function button(ctx, item, text, align = 18, selected = false) {
  const { bounds, key, over } = item;
  const click = clicked(ctx, key, over);
  const colors = ctx.colors;
  const active = selected || (ctx.press?.key === key && ctx.input.down);
  const tone = active ? COLOR.BUTTON_ACTIVE : over ? COLOR.BUTTON_HOVER : COLOR.BUTTON;
  ctx.area?.commands.push(g => {
    box(g, bounds, colors[tone], colors[COLOR.BORDER]);
    lettering(g, bounds, text, colors[COLOR.TEXT], align);
  });
  return click;
}

function toggle(ctx, text, active, radio) {
  const item = widget(ctx, radio ? "option" : "checkbox");
  const click = clicked(ctx, item.key, item.over);
  const checked = radio ? active || click : active !== click;
  const colors = ctx.colors;
  const { bounds: r } = item;
  const size = Math.min(15, r.h, r.w);
  const mark = rect(r.x + 3, r.y + (r.h - size) / 2, size, size);
  const label = rect(right(mark) + 3, r.y, r.w - size - 6, r.h);
  ctx.area?.commands.push(g => {
    const radius = radio ? size / 2 : 2;
    box(g, mark, colors[item.over ? COLOR.TOGGLE_HOVER : COLOR.TOGGLE], colors[COLOR.BORDER], radius);
    if (checked) box(g, inset(mark, 3), colors[COLOR.TOGGLE_CURSOR], null, radio ? radius - 3 : 1);
    lettering(g, label, text, colors[COLOR.TEXT]);
  });
  return click;
}

class UiContext {
  constructor(fontHeight, scale) {
    this.fontHeight = fontHeight;
    this.scale = scale;
    this.colors = cssPalette(PALETTE);
    this.windows = new Map();
    this.frameWindows = [];
    this.overlays = [];
    this.tooltips = [];
    this.input = inputSnapshot({}, scale);
    this.hues = new Map();
    this.win = null;
    this.area = null;
    this.target = null;
    this.press = null;
    this.focus = null;
    this.menu = null;
    this.zOrder = 0;
  }

  headerHeight(win) {
    const decorated = WINDOW.TITLE | WINDOW.MOVABLE | WINDOW.MINIMIZABLE | WINDOW.CLOSABLE;
    return win.flags & decorated ? Math.max(28, this.fontHeight + 12) : 0;
  }

  windowBounds(win) {
    return rect(win.x, win.y, win.w, win.minimized ? this.headerHeight(win) : win.h);
  }

  order(win) {
    return win.flags & WINDOW.BACKGROUND ? -1 : win.zOrder;
  }

  start(raw) {
    const input = this.input = inputSnapshot(raw, this.scale);
    const candidates = this.frameWindows
      .filter(win => !win.closed && !(win.flags & WINDOW.NO_INPUT) && hit(this.windowBounds(win), input))
      .sort((a, b) => this.order(b) - this.order(a));
    this.target = candidates[0] ?? null;
    this.previousFocus = this.focus;
    this.blockClick = false;
    if (input.key("Escape")) this.menu = null;
    if (this.menu) {
      if (hit(this.menu.bounds, input) || hit(this.menu.trigger, input)) {
        this.target = this.menu.win;
      } else if (input.pressed) {
        this.menu = null;
        this.blockClick = input.pressed;
      }
    }
    if (input.pressed) {
      this.press = null;
      this.ownsPress = Boolean(this.target) || this.blockClick;
      if (this.target) this.target.zOrder = ++this.zOrder;
      if (!this.menu) this.focus = null;
    } else if (!input.down && !input.released) {
      this.press = null;
      this.ownsPress = false;
    }
    if (input.key("Escape")) this.focus = null;
    this.keyboardWindow = this.frameWindows.reduce((top, win) =>
      !win.closed && !(win.flags & WINDOW.NO_INPUT) && (!top || this.order(win) > this.order(top)) ? win : top, null);
    this.frameWindows = [];
    this.overlays = [];
    this.tooltips = [];
    this.popup = null;
    this.barParent = null;
    this.win = this.area = null;
    this.focusSeen = this.menuSeen = false;
  }

  begin(title, bounds, flags) {
    let win = this.windows.get(title);
    if (!win) {
      win = { ...bounds, title, flags, zOrder: ++this.zOrder, scrollY: 0, maxScroll: 0 };
      this.windows.set(title, win);
    }
    if (!(flags & WINDOW.MOVABLE)) Object.assign(win, { x: bounds.x, y: bounds.y });
    if (!(flags & WINDOW.SCALABLE)) Object.assign(win, { w: bounds.w, h: bounds.h });
    win.flags = flags;
    win.widgetIndex = 0;
    win.commands = [];
    win.contentCount = 0;
    this.win = win;
    this.area = null;
    if (win.closed) return false;
    this.frameWindows.push(win);

    const input = this.input;
    const headerH = this.headerHeight(win);
    const leftResize = Boolean(flags & WINDOW.SCALE_LEFT);
    const canPoint = !(flags & WINDOW.NO_INPUT) && !this.menu && !this.blockClick
      && (this.target === win || this.target === null);
    if (canPoint && hit(this.windowBounds(win), input)) {
      this.target = win;
      if (input.pressed) {
        this.ownsPress = true;
        this.keyboardWindow = win;
      }
    }
    let boundsNow = this.windowBounds(win);
    if (canPoint && input.pressed && !this.press && hit(boundsNow, input)) {
      let edge = right(boundsNow) - 5;
      let close, collapse;
      if (flags & WINDOW.CLOSABLE) {
        close = rect(edge - 22, win.y + 3, 22, headerH - 6);
        edge -= 25;
      }
      if (flags & WINDOW.MINIMIZABLE) collapse = rect(edge - 22, win.y + 3, 22, headerH - 6);
      const resize = rect(leftResize ? win.x : right(boundsNow) - 14, bottom(boundsNow) - 14, 14, 14);
      if (hit(close, input)) {
        win.closed = true;
        this.frameWindows.pop();
        return false;
      }
      if (hit(collapse, input)) {
        win.minimized = !win.minimized;
      } else if (!win.minimized && flags & WINDOW.SCALABLE && hit(resize, input)) {
        this.press = { win, action: "resize", x: input.x, y: input.y, left: win.x, w: win.w, h: win.h };
      } else if (flags & WINDOW.MOVABLE && input.y < win.y + headerH) {
        this.press = { win, action: "move", x: input.x, y: input.y, left: win.x, top: win.y };
      }
    }
    if (this.press?.win === win && (input.down || input.released)) {
      const drag = this.press;
      if (drag.action === "move") {
        win.x = drag.left + input.x - drag.x;
        win.y = drag.top + input.y - drag.y;
      } else if (drag.action === "resize") {
        const delta = input.x - drag.x;
        win.w = Math.max(140, drag.w + (leftResize ? -delta : delta));
        win.h = Math.max(headerH + 50, drag.h + input.y - drag.y);
        if (leftResize) win.x = drag.left + drag.w - win.w;
      }
    }
    boundsNow = this.windowBounds(win);
    this.drawWindow(win, boundsNow, headerH);
    if (win.minimized) return false;

    const content = inset(rect(win.x, win.y + headerH, win.w, win.h - headerH), PAD, GAP);
    if (!(flags & WINDOW.NO_SCROLLBAR)) content.w = Math.max(0, content.w - SCROLL_WIDTH);
    if (canPoint && hit(content, input) && !(flags & WINDOW.NO_SCROLLBAR)) {
      win.scrollY = clamp(win.scrollY - input.wheel / this.scale, 0, win.maxScroll);
    }
    this.area = region(content, []);
    this.area.y -= win.scrollY;
    return true;
  }

  drawWindow(win, bounds, headerH) {
    const colors = this.colors;
    const flags = win.flags;
    win.commands.push(g => {
      g.save();
      g.shadowColor = "rgba(0, 0, 0, 0.35)";
      g.shadowBlur = 12;
      g.shadowOffsetY = 4;
      box(g, bounds, colors[COLOR.WINDOW], flags & WINDOW.BORDER ? colors[COLOR.BORDER] : null, 5);
      g.restore();
      if (!headerH) return;
      const header = rect(bounds.x + 1, bounds.y + 1, bounds.w - 2, headerH - 1);
      box(g, header, colors[COLOR.HEADER], null, 4);
      let edge = right(bounds) - 5;
      for (const [flag, symbol] of [[WINDOW.CLOSABLE, "×"], [WINDOW.MINIMIZABLE, win.minimized ? "+" : "−"]]) {
        if (!(flags & flag)) continue;
        const control = rect(edge - 22, bounds.y + 3, 22, headerH - 6);
        box(g, control, colors[hit(control, this.input) ? COLOR.BUTTON_HOVER : COLOR.BUTTON], colors[COLOR.BORDER]);
        lettering(g, control, symbol, colors[COLOR.TEXT], 18);
        edge -= 25;
      }
      if (flags & WINDOW.TITLE) {
        lettering(g, rect(bounds.x + 5, bounds.y, edge - bounds.x - 5, headerH), win.title, colors[COLOR.TEXT]);
      }
    });
  }

  end() {
    const win = this.win;
    const area = this.area;
    if (win && area) {
      const bounds = area.bounds;
      advanceRow(area);
      win.maxScroll = win.flags & WINDOW.NO_SCROLLBAR ? 0
        : Math.max(0, area.y + win.scrollY - GAP - bottom(bounds));
      win.scrollY = clamp(win.scrollY, 0, win.maxScroll);
      win.commands.push(g => {
        g.save();
        clip(g, bounds);
        for (const draw of area.commands) draw(g);
        g.restore();
      });
      win.contentCount += area.commands.length;
      this.drawScrollbar(win, bounds);
      if (win.flags & WINDOW.SCALABLE) this.drawResizeHandle(win);
    }
    this.win = this.area = null;
  }

  drawScrollbar(win, bounds) {
    if (win.maxScroll <= 0 || !bounds.h) return;
    const track = rect(right(bounds) + 2, bounds.y, SCROLL_WIDTH - 2, bounds.h);
    const size = Math.min(track.h, Math.max(16, track.h ** 2 / (track.h + win.maxScroll)));
    const travel = track.h - size;
    const thumb = rect(track.x, track.y + travel * win.scrollY / win.maxScroll, track.w, size);
    const key = JSON.stringify([win.title, "scroll"]);
    const over = !this.menu && !this.blockClick && this.target === win
      && !(win.flags & WINDOW.NO_INPUT) && hit(track, this.input);
    const press = interact(this, key, over, { offset: hit(thumb, this.input) ? this.input.y - thumb.y : size / 2 });
    if (press && (this.input.down || this.input.released)) {
      win.scrollY = fraction(this.input.y - track.y - press.offset, travel) * win.maxScroll;
      thumb.y = track.y + travel * win.scrollY / win.maxScroll;
    }
    if (win.flags & WINDOW.SCROLL_AUTO_HIDE && this.target !== win && !press) return;
    const color = press ? COLOR.SCROLLBAR_CURSOR_ACTIVE : over ? COLOR.SCROLLBAR_CURSOR_HOVER : COLOR.SCROLLBAR_CURSOR;
    win.commands.push(g => {
      box(g, track, this.colors[COLOR.SCROLLBAR]);
      box(g, thumb, this.colors[color]);
    });
  }

  drawResizeHandle(win) {
    const left = Boolean(win.flags & WINDOW.SCALE_LEFT);
    const x = left ? win.x + 3 : win.x + win.w - 3;
    const y = win.y + win.h - 3;
    const direction = left ? 1 : -1;
    const color = this.colors[COLOR.BORDER];
    win.commands.push(g => {
      g.beginPath();
      for (const size of [4, 8, 12]) {
        g.moveTo(x + direction * size, y);
        g.lineTo(x, y - size);
      }
      g.strokeStyle = color;
      g.lineWidth = 1;
      g.stroke();
    });
  }

  menubarBegin() {
    if (!this.area) return;
    this.barParent = this.area;
    const bounds = this.area.bounds;
    this.area = region(bounds, []);
  }

  menubarEnd() {
    if (!this.barParent) return;
    const bar = this.area;
    advanceRow(bar);
    const area = this.area = this.barParent;
    const height = Math.max(0, bar.y - bar.bounds.y);
    const content = rect(area.bounds.x, area.bounds.y + height, area.bounds.w, area.bounds.h - height);
    const barBounds = rect(bar.bounds.x, bar.bounds.y, bar.bounds.w, height);
    this.win.contentCount += bar.commands.length;
    this.win.commands.push(g => {
      g.save();
      clip(g, barBounds);
      for (const draw of bar.commands) draw(g);
      g.restore();
    });
    area.y += height;
    area.bounds = content;
    this.barParent = null;
  }

  menuBegin(text, align, w, h, viewportWidth, viewportHeight) {
    if (!this.area) return false;
    // Use a separate sequence inside the popup so opening it leaves other widget IDs intact.
    const savedIndex = this.win.widgetIndex;
    const key = JSON.stringify([this.win.title, "menu", savedIndex]);
    this.menuTrigger = key;
    const item = widget(this, "menu");
    this.menuTrigger = null;
    let open = this.menu?.key === item.key;
    if (button(this, item, text, align, open)) {
      this.menu = open ? null : { key: item.key, win: this.win };
      open = !open;
    }
    if (!open) return false;
    const r = item.bounds;
    const x = clamp(r.x, 0, Math.max(0, viewportWidth - w));
    const y = bottom(r) + h > viewportHeight && r.y >= h ? r.y - h : bottom(r) + 2;
    const bounds = rect(x, y, w, h);
    Object.assign(this.menu, { trigger: r, bounds });
    this.menuSeen = true;
    this.popup = { parent: this.area, index: this.win.widgetIndex, bounds };
    this.area = region(inset(bounds, 5), []);
    return true;
  }

  menuEnd() {
    if (!this.popup) return;
    const { parent, index, bounds } = this.popup;
    const { commands } = this.area;
    const colors = this.colors;
    if (this.menu) this.overlays.push(g => {
      g.save();
      g.shadowColor = "rgba(0, 0, 0, 0.45)";
      g.shadowBlur = 10;
      box(g, bounds, colors[COLOR.COMBO], colors[COLOR.BORDER], 4);
      g.restore();
      g.save();
      clip(g, inset(bounds, 2));
      for (const draw of commands) draw(g);
      g.restore();
    });
    this.win.widgetIndex = index;
    this.area = parent;
    this.popup = null;
  }

  tooltip(text, viewportWidth, viewportHeight) {
    const { x, y } = this.input;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    const colors = this.colors;
    this.tooltips.push(g => {
      const w = Math.min(viewportWidth, g.measureText(text).width + 16);
      const h = this.fontHeight + 12;
      const bounds = rect(clamp(x + 13, 0, Math.max(0, viewportWidth - w)),
        y + 20 + h <= viewportHeight ? y + 20 : Math.max(0, y - h - 6), w, h);
      box(g, bounds, colors[COLOR.HEADER], colors[COLOR.BORDER], 4);
      lettering(g, inset(bounds, 3, 0), text, colors[COLOR.TEXT]);
    });
  }
}

function textPosition(ctx, text, x) {
  const g = ctx.measure;
  if (!g) return Math.round(x / (ctx.fontHeight * 0.55));
  let offset = 0;
  for (const char of text) {
    const width = g.measureText(char).width;
    if (x <= width / 2) break;
    x -= width;
    offset++;
  }
  return offset;
}

function edit(ctx, item, original, flags, maxLength, filter, type = "edit") {
  const { bounds, key, over } = item;
  const input = ctx.input;
  const colors = ctx.colors;
  const readOnly = Boolean(flags & EDIT.READ_ONLY);
  const multiline = Boolean(flags & EDIT.MULTILINE);
  const selectable = Boolean(flags & EDIT.SELECTABLE);
  let chars = Array.from(original);
  let committed = false;
  const press = interact(ctx, key, over);
  const previous = ctx.previousFocus;
  const wasActive = previous?.key === key;
  if (press && input.pressed) {
    const pos = clamp(textPosition(ctx, original, input.x - bounds.x - 6 + (wasActive ? previous.scroll : 0)),
      0, chars.length);
    const cursor = !wasActive && flags & (EDIT.AUTO_SELECT | EDIT.GOTO_END) ? chars.length : pos;
    ctx.focus = { key, win: ctx.win, type, cursor, anchor: !wasActive && flags & EDIT.AUTO_SELECT ? 0 : cursor,
      scroll: wasActive ? previous.scroll : 0, since: Date.now(), text: original };
  }
  const focus = ctx.focus?.key === key ? ctx.focus : null;
  if (focus) {
    ctx.focusSeen = true;
    if (focus.text !== original) {
      focus.cursor = focus.anchor = chars.length;
      focus.scroll = 0;
    }
    if (selectable && press && input.down && !input.pressed && !ctx.menu) {
      focus.cursor = clamp(textPosition(ctx, original, input.x - bounds.x - 6 + focus.scroll), 0, chars.length);
    }
    if (!ctx.menu && ctx.keyboardWindow === ctx.win) {
      const move = cursor => {
        focus.cursor = clamp(cursor, 0, chars.length);
        if (!selectable || !input.shift) focus.anchor = focus.cursor;
        focus.since = Date.now();
      };
      const replace = (start, end, insert) => {
        chars.splice(start, end - start, ...insert);
        move(start + insert.length);
        focus.anchor = focus.cursor;
      };
      let start = Math.min(focus.cursor, focus.anchor);
      let end = Math.max(focus.cursor, focus.anchor);
      if (selectable && input.ctrl && input.key("KeyA")) {
        focus.anchor = 0;
        focus.cursor = chars.length;
      } else if (input.key("Home")) {
        move(0);
      } else if (input.key("End")) {
        move(chars.length);
      } else if (input.key("ArrowLeft")) {
        move(!input.shift && start !== end ? start : focus.cursor - 1);
      } else if (input.key("ArrowRight")) {
        move(!input.shift && start !== end ? end : focus.cursor + 1);
      }
      start = Math.min(focus.cursor, focus.anchor);
      end = Math.max(focus.cursor, focus.anchor);
      if (flags & EDIT.CLIPBOARD && input.ctrl && (input.key("KeyC") || input.key("KeyX")) && start < end) {
        const selection = chars.slice(start, end).join("");
        globalThis.navigator?.clipboard?.writeText(selection)?.catch(() => {});
        if (!readOnly && input.key("KeyX")) replace(start, end, []);
      } else if (!readOnly && input.key("Backspace")) {
        replace(start === end ? Math.max(0, start - 1) : start, end, []);
      } else if (!readOnly && input.key("Delete")) {
        replace(start, start === end ? Math.min(chars.length, end + 1) : end, []);
      }
      let added = input.text;
      if (input.key("Tab") && flags & EDIT.ALLOW_TAB && !added.includes("\t")) added += "\t";
      if (input.key("Enter")) {
        const newline = multiline && (!(flags & EDIT.CTRL_ENTER_NEWLINE) || input.ctrl);
        if (newline && !added.includes("\n")) added += "\n";
        else if (!newline && flags & EDIT.SIG_ENTER) committed = true;
      }
      if (!readOnly && added) {
        start = Math.min(focus.cursor, focus.anchor);
        end = Math.max(focus.cursor, focus.anchor);
        let remaining = maxLength - encoder.encode([...chars.slice(0, start), ...chars.slice(end)].join("")).length;
        const insert = [];
        for (const char of added) {
          if (char === "\n" ? !multiline : char === "\t" ? !(flags & EDIT.ALLOW_TAB) : char < " " || char === "\x7f") continue;
          if (FILTERS[filter] && !FILTERS[filter].test(char)) continue;
          const size = encoder.encode(char).length;
          if (size > remaining) break;
          insert.push(char);
          remaining -= size;
        }
        if (insert.length) replace(start, end, insert);
      }
    }
  }
  const text = chars.join("");
  if (focus) focus.text = text;
  ctx.area?.commands.push(g => {
    box(g, bounds, colors[COLOR.EDIT], colors[focus || over ? COLOR.EDIT_CURSOR : COLOR.BORDER]);
    g.save();
    const inner = inset(bounds, 6, 2);
    clip(g, inner);
    g.textAlign = "left";
    g.textBaseline = "middle";
    const lines = text.split("\n");
    const lineHeight = ctx.fontHeight + 3;
    const before = focus ? chars.slice(0, focus.cursor).join("").split("\n") : [];
    const line = before.length - 1;
    const caretX = focus ? g.measureText(before[line]).width : 0;
    const startY = multiline ? inner.y + lineHeight / 2 : bounds.y + bounds.h / 2;
    const scrollY = multiline ? Math.max(0, (line + 1) * lineHeight - inner.h) : 0;
    if (focus && !(flags & EDIT.NO_HORIZONTAL_SCROLL)) {
      focus.scroll = clamp(focus.scroll, Math.max(0, caretX - inner.w + 1), caretX);
    }
    const left = inner.x - (flags & EDIT.NO_HORIZONTAL_SCROLL ? 0 : focus?.scroll ?? 0);
    if (focus && focus.anchor !== focus.cursor) {
      const start = Math.min(focus.anchor, focus.cursor);
      const end = Math.max(focus.anchor, focus.cursor);
      let offset = 0;
      for (let i = 0; i < lines.length; i++) {
        const chars = Array.from(lines[i]);
        const from = clamp(start - offset, 0, chars.length);
        const to = clamp(end - offset, 0, chars.length);
        if (from < to) {
          const x = left + g.measureText(chars.slice(0, from).join("")).width;
          const w = g.measureText(chars.slice(from, to).join("")).width;
          fill(g, rect(x, startY + i * lineHeight - scrollY - lineHeight / 2, w, lineHeight),
            colors[COLOR.BUTTON_ACTIVE]);
        }
        offset += chars.length + 1;
      }
    }
    g.fillStyle = colors[COLOR.TEXT];
    lines.forEach((text, i) => g.fillText(text, left, startY + i * lineHeight - scrollY));
    if (focus && !(flags & EDIT.NO_CURSOR) && (Date.now() - focus.since) % 1000 < 560) {
      const middle = startY + line * lineHeight - scrollY;
      fill(g, rect(left + caretX, middle - ctx.fontHeight / 2, 1, ctx.fontHeight), colors[COLOR.EDIT_CURSOR]);
    }
    g.restore();
  });
  const result = focus ? EDIT.ACTIVE | (wasActive ? 0 : EDIT.ACTIVATED)
    : EDIT.INACTIVE | (wasActive ? EDIT.DEACTIVATED : 0);
  return { text, changed: original !== text, result: result | (committed ? EDIT.COMMITTED : 0) };
}

function meter(ctx, item, ratio, slider) {
  const { bounds, over, key } = item;
  const colors = ctx.colors;
  const cursor = ctx.press?.key === key ? COLOR.SLIDER_CURSOR_ACTIVE
    : over ? COLOR.SLIDER_CURSOR_HOVER : COLOR.SLIDER_CURSOR;
  ctx.area?.commands.push(g => {
    const r = inset(bounds, 1, (bounds.h - Math.min(bounds.h, 14)) / 2);
    box(g, r, colors[COLOR.SLIDER], colors[COLOR.BORDER]);
    const track = inset(r, 2);
    if (slider) {
      const size = Math.min(12, track.w);
      box(g, rect(track.x + Math.max(0, track.w - size) * ratio, track.y, size, track.h), colors[cursor]);
    } else {
      box(g, rect(track.x, track.y, track.w * ratio, track.h), colors[cursor]);
    }
  });
}

function picker(ctx, color, alpha) {
  const item = widget(ctx, "picker");
  const { bounds, over, key } = item;
  const r = inset(bounds, 2);
  const bar = Math.min(18, r.w / 4);
  const square = rect(r.x, r.y, r.w - bar - 8, r.h - (alpha ? bar + 6 : 0));
  const hue = rect(right(r) - bar, r.y, bar, square.h);
  const opacity = rect(r.x, bottom(square) + 6, r.w, bar);
  const input = ctx.input;
  const part = hit(square, input) ? "square" : hit(hue, input) ? "hue" : alpha && hit(opacity, input) ? "alpha" : null;
  const press = interact(ctx, key, over && part !== null, { part });
  let [h, s, v] = rgbToHsv(color, ctx.hues.get(key) ?? 0);
  let a = color[3];
  let changed = false;
  let rgbChanged = false;
  if (press && (input.down || input.released)) {
    if (press.part === "square") {
      s = fraction(input.x - square.x, square.w);
      v = 1 - fraction(input.y - square.y, square.h);
      changed = rgbChanged = true;
    } else if (press.part === "hue") {
      h = Math.min(fraction(input.y - hue.y, hue.h), 0.999999);
      changed = rgbChanged = true;
    } else {
      a = fraction(input.x - opacity.x, opacity.w);
      changed = true;
    }
  }
  ctx.hues.set(key, h);
  const [red, green, blue] = rgbChanged ? hsvToRgb(h, s, v) : color;
  const rgb = `${red * 255}, ${green * 255}, ${blue * 255}`;
  const colors = ctx.colors;
  ctx.area?.commands.push(g => {
    fill(g, square, `hsl(${h * 360}, 100%, 50%)`);
    gradient(g, square, false, ["white", "rgba(255,255,255,0)"]);
    gradient(g, square, true, ["rgba(0,0,0,0)", "black"]);
    gradient(g, hue, true, ["red", "yellow", "lime", "cyan", "blue", "magenta", "red"]);
    const markerX = square.x + s * square.w;
    const markerY = square.y + (1 - v) * square.h;
    g.beginPath();
    g.arc(markerX, markerY, 4, 0, 2 * Math.PI);
    g.lineWidth = 3;
    g.strokeStyle = "#222";
    g.stroke();
    g.lineWidth = 1;
    g.strokeStyle = "white";
    g.stroke();
    const mark = (area, position, horizontal) => {
      const line = horizontal
        ? rect(area.x + position * area.w - 2, area.y - 1, 4, area.h + 2)
        : rect(area.x - 1, area.y + position * area.h - 2, area.w + 2, 4);
      g.strokeStyle = "white";
      g.strokeRect(line.x, line.y, line.w, line.h);
    };
    mark(hue, h, false);
    if (alpha) {
      fill(g, opacity, colors[COLOR.EDIT]);
      gradient(g, opacity, false, [`rgba(${rgb}, 0)`, `rgb(${rgb})`]);
      mark(opacity, a, true);
    }
  });
  return changed ? Float32Array.of(red, green, blue, a) : null;
}

function property(ctx, name, min, value, max, step, speed) {
  const item = widget(ctx, "property");
  const { bounds, key, over } = item;
  const input = ctx.input;
  const style = ctx.colors;
  const arrowWidth = Math.min(bounds.h, bounds.w / 4);
  const left = rect(bounds.x, bounds.y, arrowWidth, bounds.h);
  const rightArrow = rect(right(bounds) - arrowWidth, bounds.y, arrowWidth, bounds.h);
  const middle = rect(right(left) + 1, bounds.y, bounds.w - 2 * arrowWidth - 2, bounds.h);
  const show = number => Number(number.toPrecision(6)).toString();
  let next = value;
  ctx.area?.commands.push(g => box(g, bounds, style[COLOR.PROPERTY], style[COLOR.BORDER]));
  if (button(ctx, { bounds: left, key: key + "<", over: over && hit(left, input) }, "‹")) next -= step;
  if (button(ctx, { bounds: rightArrow, key: key + ">", over: over && hit(rightArrow, input) }, "›")) next += step;
  if (ctx.focus?.key === key && ctx.focus.type === "property") {
    const { text, result } = edit(ctx, { bounds: middle, key, over: over && hit(middle, input) },
      ctx.focus.text, EDIT.SIG_ENTER | EDIT.SELECTABLE, 32, 2, "property");
    if (result & EDIT.COMMITTED) {
      const number = parseFloat(text);
      if (Number.isFinite(number)) next = number;
      ctx.focus = null;
    }
  } else {
    const press = interact(ctx, key, over && hit(middle, input), { value });
    if (press && (input.down || input.released)) {
      const drag = input.x - press.x;
      press.dragged ||= Math.abs(drag) >= 2;
      if (press.dragged) next = press.value + drag * speed;
      else if (input.released && over && hit(middle, input)) {
        const text = show(value);
        ctx.focus = { key, win: ctx.win, type: "property", text, anchor: 0, cursor: text.length, scroll: 0, since: Date.now() };
        ctx.focusSeen = true;
      }
    }
    const nameText = name.startsWith("#") ? name.slice(1) : name;
    const text = show(clamp(next, min, max));
    ctx.area?.commands.push(g => {
      const split = Math.min(middle.w, g.measureText(text).width + 12);
      lettering(g, rect(middle.x, middle.y, middle.w - split, middle.h), nameText, style[COLOR.TEXT]);
      lettering(g, rect(right(middle) - split, middle.y, split, middle.h), text, style[COLOR.TEXT], 20);
    });
  }
  return Math.fround(clamp(next, min, max));
}

export function createUiImports(mem, options = {}) {
  const gfx = options.gfx;
  const contexts = new Map();
  let lastError = "";
  let nextId = 0;
  let overlayCanvas;
  let graphics;
  let lastDrawCount = 0;
  const fonts = globalThis.document?.fonts;
  const width = () => Number(gfx?.width ?? 760);
  const height = () => Number(gfx?.height ?? 520);
  const context = id => {
    const ctx = contexts.get(id >>> 0);
    if (!ctx) lastError = "invalid UI context";
    return ctx;
  };
  const fail = (text, result = 0) => {
    lastError = text;
    return result;
  };

  function create(fontHeight, scale, ttf) {
    if (!Number.isFinite(fontHeight) || fontHeight <= 0) return fail("font height must be finite and positive");
    if (!Number.isFinite(scale) || scale <= 0) return fail("UI scale must be finite and positive");
    if (ttf && !ttf.length) return fail("font data is empty");
    if (nextId === 0xffffffff) return fail("UI context ids exhausted");
    const id = ++nextId;
    const ctx = new UiContext(fontHeight, scale);
    contexts.set(id, ctx);
    lastError = "";
    if (ttf && fonts && typeof globalThis.FontFace === "function") {
      const family = `GooseUI-${++nextFont}`;
      try {
        const face = new FontFace(family, ttf);
        face.load().then(loaded => {
          if (contexts.get(id) !== ctx) return;
          fonts.add(loaded);
          ctx.face = loaded;
          ctx.family = family;
        }).catch(error => {
          if (contexts.get(id) === ctx) fail(`could not load UI font: ${error.message}`);
        });
      } catch (error) {
        fail(`could not load UI font: ${error.message}`);
      }
    }
    return id;
  }

  function destroy(id) {
    const ctx = context(id);
    if (ctx?.face) fonts.delete(ctx.face);
    contexts.delete(id >>> 0);
  }

  function canvasContext() {
    if (!overlayCanvas) {
      if (typeof globalThis.OffscreenCanvas === "function") overlayCanvas = new OffscreenCanvas(1, 1);
      else overlayCanvas = globalThis.document?.createElement("canvas");
      graphics = overlayCanvas?.getContext("2d");
    }
    return graphics;
  }

  function setFont(g, ctx) {
    g.font = `${ctx.fontHeight}px ${ctx.family ? `"${ctx.family}", ` : ""}system-ui, sans-serif`;
  }

  function render(ctx) {
    if (ctx.focus && (!ctx.focusSeen || ctx.focus.win.minimized)) ctx.focus = null;
    if (!ctx.menuSeen) ctx.menu = null;
    const windows = ctx.frameWindows.slice().sort((a, b) => ctx.order(a) - ctx.order(b));
    lastDrawCount = windows.reduce((count, win) => count + win.commands.length + (win.contentCount ?? 0), 0)
      + ctx.overlays.length + ctx.tooltips.length;
    if (ctx.input.released) {
      ctx.press = null;
      ctx.ownsPress = false;
    }
    const g = canvasContext();
    const w = width(), h = height();
    if (!g || w <= 0 || h <= 0) return;
    if (overlayCanvas.width !== w) overlayCanvas.width = w;
    if (overlayCanvas.height !== h) overlayCanvas.height = h;
    g.resetTransform();
    g.clearRect(0, 0, w, h);
    g.save();
    g.scale(ctx.scale, ctx.scale);
    setFont(g, ctx);
    for (const win of windows) for (const draw of win.commands) draw(g);
    for (const draw of ctx.overlays) draw(g);
    for (const draw of ctx.tooltips) draw(g);
    g.restore();
    gfx?.compositeCanvas2D?.(overlayCanvas);
  }

  const str = (args, start = 0) => mem.readSliceUtf8(args, start);
  const imports = {
    gs_ui_available: () => 1,
    gs_ui_error: out => mem.appendBuilder(out, lastError),
    gs_ui_create: (fontHeight, scale) => create(fontHeight, scale),
    gs_ui_create_from_memory(...args) {
      const ttf = mem.readSlice(args);
      return create(args[ttf.next], 1, ttf.bytes);
    },
    gs_ui_destroy: destroy,
    gs_ui_default_color_table(...args) {
      const { view } = mem.readSliceView(args);
      view.set(PALETTE.subarray(0, view.length));
    },
    gs_ui_style_from_table(id, ...args) {
      const ctx = context(id);
      if (!ctx) return;
      const { view } = mem.readSliceView(args);
      if (view.length >= PALETTE.length) ctx.colors = cssPalette(view.subarray(0, PALETTE.length));
    },
    gs_ui_scale: id => context(id)?.scale ?? 0,
    gs_ui_set_scale(id, scale) {
      const ctx = context(id);
      if (!ctx) return 0;
      if (!Number.isFinite(scale) || scale <= 0) return fail("UI scale must be finite and positive");
      ctx.scale = scale;
      return 1;
    },
    gs_ui_input_from_gfx(id) {
      const ctx = context(id);
      if (!ctx) return;
      ctx.start(gfx?.snapshotInputForUi?.() ?? {});
      ctx.measure = canvasContext();
      if (ctx.measure) setFont(ctx.measure, ctx);
    },
    gs_ui_wants_keyboard(id) {
      const ctx = context(id);
      return Number(Boolean(ctx?.focus && !ctx.menu && ctx.focus.win === ctx.keyboardWindow));
    },
    gs_ui_wants_mouse(id) {
      const ctx = context(id);
      return Number(Boolean(ctx && (ctx.input.down ? ctx.ownsPress : ctx.target || ctx.blockClick)));
    },
    gs_ui_begin(id, ...args) {
      const ctx = context(id);
      if (!ctx) return 0;
      const { next, text } = str(args);
      return Number(ctx.begin(text, rect(...args.slice(next, next + 4)), Number(args[next + 4])));
    },
    gs_ui_end: id => context(id)?.end(),
    gs_ui_menubar_begin: id => context(id)?.menubarBegin(),
    gs_ui_menubar_end: id => context(id)?.menubarEnd(),
    gs_ui_menu_begin_label(id, ...args) {
      const ctx = context(id);
      if (!ctx) return 0;
      const { next, text } = str(args);
      return Number(ctx.menuBegin(text, Number(args[next]), args[next + 1], args[next + 2],
        width() / ctx.scale, height() / ctx.scale));
    },
    gs_ui_menu_item_label(id, ...args) {
      const ctx = context(id);
      if (!ctx?.popup) return 0;
      const { next, text } = str(args);
      const click = button(ctx, widget(ctx, "menu-item"), text, Number(args[next]));
      if (click) {
        ctx.menu = null;
        ctx.blockClick = true;
      }
      return Number(click);
    },
    gs_ui_menu_end: id => context(id)?.menuEnd(),
    gs_ui_layout_row_dynamic(id, height, cols) {
      const ctx = context(id);
      if (ctx) layout(ctx, height, Number(cols), undefined, null, true);
    },
    gs_ui_layout_row_static(id, height, itemWidth, cols) {
      const ctx = context(id);
      if (ctx) layout(ctx, height, Number(cols), Number(itemWidth), null, false);
    },
    gs_ui_layout_row(id, format, height, ...args) {
      const ctx = context(id);
      if (!ctx) return;
      const { ptr, len } = mem.readSliceArgs(args);
      const sizes = mem.readF32Array(ptr, len);
      if (Number(format) === 0) {
        let remaining = 1;
        let unspecified = 0;
        for (const ratio of sizes) {
          if (ratio < 0) unspecified++;
          else remaining -= ratio;
        }
        if (unspecified) {
          for (let i = 0; i < sizes.length; i++) if (sizes[i] < 0) sizes[i] = Math.max(0, remaining / unspecified);
        }
      }
      layout(ctx, height, len, undefined, sizes, Number(format) === 0);
    },
    gs_ui_edit_string(id, flags, ...args) {
      const { next, bytes } = mem.readSlice(args);
      const original = decoder.decode(bytes);
      const out = args[next + 2];
      const ctx = context(id);
      const result = ctx ? edit(ctx, widget(ctx, "edit"), original, Number(flags), Number(args[next]),
        Number(args[next + 1])) : null;
      mem.appendBuilder(out, result?.changed ? result.text : bytes);
      return BigInt(result?.result ?? EDIT.INACTIVE);
    },
    gs_ui_widget_is_hovered(id) {
      const ctx = context(id);
      return Number(Boolean(ctx && hovered(ctx, nextBounds(ctx, false))));
    },
    gs_ui_tooltip(id, ...args) {
      const ctx = context(id);
      if (ctx) ctx.tooltip(str(args).text, width() / ctx.scale, height() / ctx.scale);
    },
    gs_ui_button_label(id, ...args) {
      const ctx = context(id);
      return ctx ? Number(button(ctx, widget(ctx, "button"), str(args).text)) : 0;
    },
    gs_ui_button_symbol(id, symbol) {
      const ctx = context(id);
      return ctx ? Number(button(ctx, widget(ctx, "symbol"), SYMBOLS[Number(symbol)] ?? "")) : 0;
    },
    gs_ui_option_label(id, ...args) {
      const ctx = context(id);
      if (!ctx) return 0;
      const { next, text } = str(args);
      return Number(toggle(ctx, text, Boolean(args[next]), true));
    },
    gs_ui_checkbox_label(id, ...args) {
      const ctx = context(id);
      if (!ctx) return 0;
      const { next, text } = str(args);
      const ptr = mem.address(args[next]);
      const value = mem.view().getUint8(ptr);
      if (!toggle(ctx, text, Boolean(value), false)) return 0;
      mem.view().setUint8(ptr, value ? 0 : 1);
      return 1;
    },
    gs_ui_label(id, ...args) {
      const ctx = context(id);
      if (!ctx) return;
      const { next, text } = str(args);
      const { bounds } = widget(ctx, "label");
      const color = ctx.colors[COLOR.TEXT];
      ctx.area?.commands.push(g => lettering(g, bounds, text, color, Number(args[next])));
    },
    gs_ui_progress(id, ptr, max, modifiable) {
      const ctx = context(id);
      if (!ctx) return 0;
      const item = widget(ctx, "progress");
      const cur = mem.view().getBigInt64(mem.address(ptr), true);
      let next = cur;
      if (modifiable && max > 0n && interact(ctx, item.key, item.over) && (ctx.input.down || ctx.input.released)) {
        const ratio = fraction(ctx.input.x - item.bounds.x, item.bounds.w);
        const units = 1n << 53n;
        next = (max * BigInt(Math.round(ratio * Number(units))) + units / 2n) / units;
      }
      meter(ctx, item, fraction(Number(next), Number(max)), false);
      if (next === cur) return 0;
      mem.writeI64(ptr, next);
      return 1;
    },
    gs_ui_color_picker(id, ...args) {
      const ctx = context(id);
      if (!ctx) return;
      const { ptr, len, next } = mem.readSliceArgs(args);
      if (len !== 4) return;
      const color = picker(ctx, mem.readF32Array(ptr, len), Number(args[next]) === 1);
      if (color) mem.writeF32Array(ptr, color);
    },
    gs_ui_property_float(id, ...args) {
      const ctx = context(id);
      if (!ctx) return 0;
      const { next, text } = str(args);
      const [min, rawPtr, max, step, speed] = args.slice(next);
      const ptr = mem.address(rawPtr);
      const value = mem.view().getFloat32(ptr, true);
      const changed = property(ctx, text, min, value, max, step, speed);
      if (changed === value) return 0;
      mem.view().setFloat32(ptr, changed, true);
      return 1;
    },
    gs_ui_slider_float(id, min, rawPtr, max, step) {
      const ctx = context(id);
      if (!ctx) return 0;
      const item = widget(ctx, "slider");
      const ptr = mem.address(rawPtr);
      const value = mem.view().getFloat32(ptr, true);
      let next = value;
      if (max > min && interact(ctx, item.key, item.over) && (ctx.input.down || ctx.input.released)) {
        const ratio = fraction(ctx.input.x - item.bounds.x, item.bounds.w);
        const range = max - min;
        next = Math.fround(clamp(min + (step > 0 && ratio < 1 ? Math.round(ratio * range / step) * step : ratio * range), min, max));
      }
      meter(ctx, item, fraction(next - min, max - min), true);
      if (next === value) return 0;
      mem.view().setFloat32(ptr, next, true);
      return 1;
    },
    gs_ui_render(id) {
      const ctx = context(id);
      if (ctx) render(ctx);
    },
  };

  const ui = {
    get drawCommandCount() { return lastDrawCount; },
    dispose() {
      for (const id of contexts.keys()) destroy(id);
      overlayCanvas = graphics = null;
      lastDrawCount = 0;
    },
  };
  return { imports, ui };
}
