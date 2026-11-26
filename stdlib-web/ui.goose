// Immediate-mode UI backed by the Web host.
namespace ui;

import std;
import vec;

struct Context { id: u32 }
struct Color { r: u8, g: u8, b: u8, a: u8 }
struct Colorf { r: f32, g: f32, b: f32, a: f32 }
struct Rect { x: f32, y: f32, w: f32, h: f32 }

let WINDOW_BORDER = 1;
let WINDOW_MOVABLE = 2;
let WINDOW_SCALABLE = 4;
let WINDOW_CLOSABLE = 8;
let WINDOW_MINIMIZABLE = 16;
let WINDOW_NO_SCROLLBAR = 32;
let WINDOW_TITLE = 64;
let WINDOW_SCROLL_AUTO_HIDE = 128;
let WINDOW_BACKGROUND = 256;
let WINDOW_SCALE_LEFT = 512;
let WINDOW_NO_INPUT = 1024;

let DYNAMIC = 0;
let STATIC = 1;
let TEXT_LEFT = 17;
let TEXT_CENTERED = 18;
let TEXT_RIGHT = 20;

let EDIT_DEFAULT = 0;
let EDIT_READ_ONLY = 1;
let EDIT_AUTO_SELECT = 2;
let EDIT_SIG_ENTER = 4;
let EDIT_ALLOW_TAB = 8;
let EDIT_NO_CURSOR = 16;
let EDIT_SELECTABLE = 32;
let EDIT_CLIPBOARD = 64;
let EDIT_CTRL_ENTER_NEWLINE = 128;
let EDIT_NO_HORIZONTAL_SCROLL = 256;
let EDIT_ALWAYS_INSERT_MODE = 512;
let EDIT_MULTILINE = 1024;
let EDIT_GOTO_END_ON_ACTIVATE = 2048;
let EDIT_SIMPLE = 512;
let EDIT_FIELD = 512 | 32 | 64;
let EDIT_BOX = 512 | 32 | 1024 | 8 | 64;

let EDIT_ACTIVE = 1;
let EDIT_INACTIVE = 2;
let EDIT_ACTIVATED = 4;
let EDIT_DEACTIVATED = 8;
let EDIT_COMMITTED = 16;

let FILTER_DEFAULT = 0;
let FILTER_ASCII = 1;
let FILTER_FLOAT = 2;
let FILTER_DECIMAL = 3;
let FILTER_HEX = 4;
let FILTER_OCT = 5;
let FILTER_BINARY = 6;

let SYMBOL_NONE = 0;
let SYMBOL_X = 1;
let SYMBOL_UNDERSCORE = 2;
let SYMBOL_CIRCLE_SOLID = 3;
let SYMBOL_CIRCLE_OUTLINE = 4;
let SYMBOL_RECT_SOLID = 5;
let SYMBOL_RECT_OUTLINE = 6;
let SYMBOL_TRIANGLE_UP = 7;
let SYMBOL_TRIANGLE_DOWN = 8;
let SYMBOL_TRIANGLE_LEFT = 9;
let SYMBOL_TRIANGLE_RIGHT = 10;
let SYMBOL_PLUS = 11;
let SYMBOL_MINUS = 12;

let RGB = 0;
let RGBA = 1;

let COLOR_TEXT = 0;
let COLOR_WINDOW = 1;
let COLOR_HEADER = 2;
let COLOR_BORDER = 3;
let COLOR_BUTTON = 4;
let COLOR_BUTTON_HOVER = 5;
let COLOR_BUTTON_ACTIVE = 6;
let COLOR_TOGGLE = 7;
let COLOR_TOGGLE_HOVER = 8;
let COLOR_TOGGLE_CURSOR = 9;
let COLOR_SELECT = 10;
let COLOR_SELECT_ACTIVE = 11;
let COLOR_SLIDER = 12;
let COLOR_SLIDER_CURSOR = 13;
let COLOR_SLIDER_CURSOR_HOVER = 14;
let COLOR_SLIDER_CURSOR_ACTIVE = 15;
let COLOR_PROPERTY = 16;
let COLOR_EDIT = 17;
let COLOR_EDIT_CURSOR = 18;
let COLOR_COMBO = 19;
let COLOR_CHART = 20;
let COLOR_CHART_COLOR = 21;
let COLOR_CHART_COLOR_HIGHLIGHT = 22;
let COLOR_SCROLLBAR = 23;
let COLOR_SCROLLBAR_CURSOR = 24;
let COLOR_SCROLLBAR_CURSOR_HOVER = 25;
let COLOR_SCROLLBAR_CURSOR_ACTIVE = 26;
let COLOR_TAB_HEADER = 27;
let COLOR_COUNT = 28;

extern fn web_ui::available() -> bool = "gs_ui_available";
extern fn web_ui::error(out: u8[>..]&) = "gs_ui_error";
extern fn web_ui::create(font_height: f32, scale: f32) -> u32 = "gs_ui_create";
extern fn web_ui::create_from_memory(ttf: const u8[:], font_height: f32) -> u32 = "gs_ui_create_from_memory";
extern fn web_ui::destroy(id: u32) = "gs_ui_destroy";
extern fn web_ui::default_color_table(out: u8[:]) = "gs_ui_default_color_table";
extern fn web_ui::style_from_table(id: u32, table: const u8[:]) = "gs_ui_style_from_table";
extern fn web_ui::scale(id: u32) -> f32 = "gs_ui_scale";
extern fn web_ui::set_scale(id: u32, scale: f32) -> bool = "gs_ui_set_scale";
extern fn web_ui::gfx_text_input(on: bool) = "gs_gfx_text_input";
extern fn web_ui::input_from_gfx(id: u32) = "gs_ui_input_from_gfx";
extern fn web_ui::wants_keyboard(id: u32) -> bool = "gs_ui_wants_keyboard";
extern fn web_ui::wants_mouse(id: u32) -> bool = "gs_ui_wants_mouse";
extern fn web_ui::begin(id: u32, title: const u8[:], x: f32, y: f32, w: f32, h: f32, flags: i64) -> bool = "gs_ui_begin";
extern fn web_ui::end(id: u32) = "gs_ui_end";
extern fn web_ui::menubar_begin(id: u32) = "gs_ui_menubar_begin";
extern fn web_ui::menubar_end(id: u32) = "gs_ui_menubar_end";
extern fn web_ui::menu_begin_label(id: u32, text: const u8[:], align: i64, w: f32, h: f32) -> bool = "gs_ui_menu_begin_label";
extern fn web_ui::menu_item_label(id: u32, text: const u8[:], align: i64) -> bool = "gs_ui_menu_item_label";
extern fn web_ui::menu_end(id: u32) = "gs_ui_menu_end";
extern fn web_ui::layout_row_dynamic(id: u32, height: f32, cols: i64) = "gs_ui_layout_row_dynamic";
extern fn web_ui::layout_row_static(id: u32, height: f32, item_width: i64, cols: i64) = "gs_ui_layout_row_static";
extern fn web_ui::layout_row(id: u32, format: i64, height: f32, ratios: const f32[:]) = "gs_ui_layout_row";
extern fn web_ui::edit_string(id: u32, flags: i64, text: const u8[:], max_len: i64, filter: i64, out: u8[>..]&) -> i64 = "gs_ui_edit_string";
extern fn web_ui::widget_is_hovered(id: u32) -> bool = "gs_ui_widget_is_hovered";
extern fn web_ui::tooltip(id: u32, text: const u8[:]) = "gs_ui_tooltip";
extern fn web_ui::button_label(id: u32, text: const u8[:]) -> bool = "gs_ui_button_label";
extern fn web_ui::button_symbol(id: u32, symbol: i64) -> bool = "gs_ui_button_symbol";
extern fn web_ui::option_label(id: u32, text: const u8[:], active: bool) -> bool = "gs_ui_option_label";
extern fn web_ui::checkbox_label(id: u32, text: const u8[:], active: bool&) -> bool = "gs_ui_checkbox_label";
extern fn web_ui::label(id: u32, text: const u8[:], align: i64) = "gs_ui_label";
extern fn web_ui::progress(id: u32, cur: i64&, max_val: i64, modifiable: bool) -> bool = "gs_ui_progress";
extern fn web_ui::color_picker(id: u32, color: f32[:], format: i64) = "gs_ui_color_picker";
extern fn web_ui::property_float(id: u32, name: const u8[:], min_val: f32, value: f32&, max_val: f32, step: f32, inc_per_pixel: f32) -> bool = "gs_ui_property_float";
extern fn web_ui::slider_float(id: u32, min_val: f32, value: f32&, max_val: f32, step: f32) -> bool = "gs_ui_slider_float";
extern fn web_ui::render(id: u32) = "gs_ui_render";

fn rect(x: f32, y: f32, w: f32, h: f32) -> Rect { Rect { x, y, w, h } }
fn rect(x: i64, y: i64, w: i64, h: i64) -> Rect { Rect { x as f32, y as f32, w as f32, h as f32 } }
fn rgba(r: i64, g: i64, b: i64, a: i64) -> Color {
    Color { clamp(r, 0, 255) as u8, clamp(g, 0, 255) as u8, clamp(b, 0, 255) as u8, clamp(a, 0, 255) as u8 }
}
fn rgb(r: i64, g: i64, b: i64) -> Color { rgba(r, g, b, 255) }

fn available() -> bool { web_ui::available() }
fn error() -> u8[>..] {
    var out: u8[>..] = [];
    web_ui::error(out);
    return out;
}
fn create(font_height: f32, scale: f32 = 1.0) -> Context { Context { web_ui::create(font_height, scale) } }
fn create_from_memory(ttf: const u8[:], font_height: f32) -> Context {
    Context { web_ui::create_from_memory(ttf, font_height) }
}
fn destroy(c: Context) { web_ui::destroy(c.id); }

fn default_color_table() -> Color[>..] {
    var bytes: u8[COLOR_COUNT * 4] = [0; COLOR_COUNT * 4];
    web_ui::default_color_table(bytes[..]);
    var out: Color[>..] = [];
    for i in COLOR_COUNT {
        let j = i * 4;
        out.push(Color { bytes[j], bytes[j + 1], bytes[j + 2], bytes[j + 3] });
    }
    return out;
}
fn style_from_table(c: Context, table: const Color[:]) {
    if table.len < COLOR_COUNT { return; }
    var bytes: u8[COLOR_COUNT * 4] = [0; COLOR_COUNT * 4];
    for i in COLOR_COUNT {
        let j = i * 4;
        let color = table[i];
        bytes[j] = color.r;
        bytes[j + 1] = color.g;
        bytes[j + 2] = color.b;
        bytes[j + 3] = color.a;
    }
    web_ui::style_from_table(c.id, bytes[..]);
}
fn scale(c: Context) -> f32 { web_ui::scale(c.id) }
fn set_scale(c: Context, s: f32) -> bool { web_ui::set_scale(c.id, s) }

fn input_from_gfx(c: Context) {
    web_ui::gfx_text_input(true);
    web_ui::input_from_gfx(c.id);
}
fn wants_keyboard(c: Context) -> bool { web_ui::wants_keyboard(c.id) }
fn wants_mouse(c: Context) -> bool { web_ui::wants_mouse(c.id) }

fn begin(c: Context, title: const u8[:], bounds: Rect, flags: i64) -> bool {
    web_ui::begin(c.id, title, bounds.x, bounds.y, bounds.w, bounds.h, flags)
}
fn end(c: Context) { web_ui::end(c.id); }
fn menubar_begin(c: Context) { web_ui::menubar_begin(c.id); }
fn menubar_end(c: Context) { web_ui::menubar_end(c.id); }
fn menu_begin_label(c: Context, text: const u8[:], align: i64, size: float2) -> bool {
    web_ui::menu_begin_label(c.id, text, align, size.x, size.y)
}
fn menu_item_label(c: Context, text: const u8[:], align: i64) -> bool {
    web_ui::menu_item_label(c.id, text, align)
}
fn menu_end(c: Context) { web_ui::menu_end(c.id); }

fn layout_row_dynamic(c: Context, height: f32, cols: i64) { web_ui::layout_row_dynamic(c.id, height, cols); }
fn layout_row_static(c: Context, height: f32, item_width: i64, cols: i64) {
    web_ui::layout_row_static(c.id, height, item_width, cols);
}
fn layout_row(c: Context, format: i64, height: f32, ratios: const f32[:]) {
    web_ui::layout_row(c.id, format, height, ratios);
}
fn edit_string<T>(c: Context, flags: i64, text: T&, filter: i64) -> i64 {
    let max_len = text.cap;
    var out: u8[>..] = [];
    let result = web_ui::edit_string(c.id, flags, text[..], max_len, filter, out);
    text.resize(0);
    text.append(out);
    return result;
}

fn widget_is_hovered(c: Context) -> bool { web_ui::widget_is_hovered(c.id) }
fn tooltip(c: Context, text: const u8[:]) { web_ui::tooltip(c.id, text); }
fn button_label(c: Context, text: const u8[:]) -> bool { web_ui::button_label(c.id, text) }
fn button_symbol(c: Context, symbol: i64) -> bool { web_ui::button_symbol(c.id, symbol) }
fn option_label(c: Context, text: const u8[:], active: bool) -> bool { web_ui::option_label(c.id, text, active) }
fn checkbox_label(c: Context, text: const u8[:], active: bool&) -> bool {
    web_ui::checkbox_label(c.id, text, active)
}
fn label(c: Context, text: const u8[:], align: i64) { web_ui::label(c.id, text, align); }
fn progress(c: Context, cur: i64&, max_val: i64, modifiable: bool) -> bool {
    web_ui::progress(c.id, cur, max_val, modifiable)
}
fn color_picker(c: Context, color: Colorf, format: i64) -> Colorf {
    var channels: f32[4] = [color.r, color.g, color.b, color.a];
    web_ui::color_picker(c.id, channels[..], format);
    return Colorf { channels[0], channels[1], channels[2], channels[3] };
}
fn property_float(c: Context, name: const u8[:], min_val: f32, value: f32&, max_val: f32, step: f32,
                  inc_per_pixel: f32) -> bool {
    web_ui::property_float(c.id, name, min_val, value, max_val, step, inc_per_pixel)
}
fn slider_float(c: Context, min_val: f32, value: f32&, max_val: f32, step: f32) -> bool {
    web_ui::slider_float(c.id, min_val, value, max_val, step)
}
fn render(c: Context) { web_ui::render(c.id); }
