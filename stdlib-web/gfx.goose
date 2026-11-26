// Graphics, window state and input through the Web host.
namespace gfx;

import std;
import math;
import vec;

let WINDOW_RESIZABLE = 1;
let WINDOW_HIDDEN = 2;
let WINDOW_FULLSCREEN = 4;
let NO_VSYNC = 8;
let DEBUG = 16;
let WAIT_WHEN_IDLE = 32;
let WINDOW_ONLY = 64;

let MOUSE_LEFT = 1;
let MOUSE_MIDDLE = 2;
let MOUSE_RIGHT = 3;
let MOUSE_X1 = 4;
let MOUSE_X2 = 5;

let EVENT_KEY_DOWN = 1;
let EVENT_KEY_UP = 2;
let EVENT_TEXT = 3;
let EVENT_MOUSE_MOTION = 4;
let EVENT_MOUSE_DOWN = 5;
let EVENT_MOUSE_UP = 6;
let EVENT_MOUSE_WHEEL = 7;
let EVENT_FOCUS_GAINED = 8;
let EVENT_FOCUS_LOST = 9;

let VERTEX = 0;
let FRAGMENT = 1;
let COMPUTE = 2;

let BUFFER_VERTEX = 1;
let BUFFER_INDEX = 2;
let BUFFER_INDIRECT = 4;
let BUFFER_STORAGE = 8;
let BUFFER_COMPUTE_READ = 16;
let BUFFER_COMPUTE_WRITE = 32;

let TEXTURE_2D = 0;
let RGBA8 = 1;
let BGRA8 = 2;
let DEPTH = 20;
let DEPTH32F = 18;
let SAMPLED = 1;
let COLOR_TARGET = 2;
let DEPTH_TARGET = 4;

let NEAREST = 0;
let LINEAR = 1;
let REPEAT = 0;
let MIRROR = 1;
let CLAMP = 2;
let COMPARE_NEVER = 1;
let COMPARE_LESS = 2;
let COMPARE_EQUAL = 3;
let COMPARE_LESS_EQUAL = 4;
let COMPARE_GREATER = 5;
let COMPARE_NOT_EQUAL = 6;
let COMPARE_GREATER_EQUAL = 7;
let COMPARE_ALWAYS = 8;

let TRIANGLES = 0;
let TRIANGLE_STRIP = 1;
let LINES = 2;
let LINE_STRIP = 3;
let POINTS = 4;
let CULL_NONE = 0;
let CULL_FRONT = 1;
let CULL_BACK = 2;
let BLEND_NONE = 0;
let BLEND_ALPHA = 1;
let BLEND_ADD = 2;
let BLEND_PREMULTIPLIED = 3;
let BLEND_MULTIPLY = 4;

let VERTEX_AUTO = 0;
let VERTEX_FLOAT = 1;
let VERTEX_FLOAT2 = 2;
let VERTEX_FLOAT3 = 3;
let VERTEX_FLOAT4 = 4;
let VERTEX_UBYTE4_NORM = 5;
let VERTEX_UBYTE4 = 6;
let VERTEX_SHORT2_NORM = 7;
let VERTEX_HALF2 = 8;
let VERTEX_HALF4 = 9;

struct Buffer { id: u32 }
struct Texture { id: u32 }
struct Sampler { id: u32 }
struct Pipeline { id: u32 }

struct PipelineDesc {
    primitive: i32 = 0,
    cull: i32 = 0,
    clockwise: bool = false,
    wireframe: bool = false,
    depth_test: bool = false,
    depth_write: bool = false,
    depth_compare: i32 = 2,
    blend: i32 = 0,
    instance_location: i32 = -1,
    depth_bias: f32 = 0.0,
    depth_bias_slope: f32 = 0.0,
    formats: u8[16] = [0; 16],
}

struct PassDesc {
    color: Texture[4] = [Texture { 0 }; 4],
    resolve: Texture[4] = [Texture { 0 }; 4],
    depth: Texture = Texture { 0 },
    layer: i32 = 0,
    mip: i32 = 0,
    clear_color: bool = true,
    clear_depth: bool = true,
    color_value: float4 = float4 { 0.0, 0.0, 0.0, 1.0 },
    depth_value: f32 = 1.0,
}

struct Event {
    kind: i32 = 0,
    scancode: i32 = 0,
    keycode: i32 = 0,
    mods: i32 = 0,
    button: i32 = 0,
    clicks: i32 = 0,
    x: f32 = 0.0,
    y: f32 = 0.0,
    dx: f32 = 0.0,
    dy: f32 = 0.0,
    wheel_x: f32 = 0.0,
    wheel_y: f32 = 0.0,
}

struct mat4 { c0: float4, c1: float4, c2: float4, c3: float4 }

let mat4_identity = mat4 {
    float4 { 1.0, 0.0, 0.0, 0.0 },
    float4 { 0.0, 1.0, 0.0, 0.0 },
    float4 { 0.0, 0.0, 1.0, 0.0 },
    float4 { 0.0, 0.0, 0.0, 1.0 },
};

fn mul(m: mat4, v: float4) -> float4 {
    m.c0 * v.x + m.c1 * v.y + m.c2 * v.z + m.c3 * v.w
}

fn mul(a: mat4, b: mat4) -> mat4 {
    mat4 { mul(a, b.c0), mul(a, b.c1), mul(a, b.c2), mul(a, b.c3) }
}

fn translate(t: float3) -> mat4 {
    mat4 { mat4_identity.c0, mat4_identity.c1, mat4_identity.c2, float4 { t.x, t.y, t.z, 1.0 } }
}

fn scale(s: float3) -> mat4 {
    mat4 { mat4_identity.c0 * s.x, mat4_identity.c1 * s.y, mat4_identity.c2 * s.z, mat4_identity.c3 }
}

fn rotate(axis: float3, angle: f32) -> mat4 {
    let a = normalize(axis);
    let c = cos(angle);
    let s = sin(angle);
    let t = 1.0 - c;
    mat4 {
        float4 { t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y, 0.0 },
        float4 { t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x, 0.0 },
        float4 { t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c, 0.0 },
        mat4_identity.c3,
    }
}

fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) -> mat4 {
    let f = 1.0 / tan(fovy * 0.5);
    let z = far / (near - far);
    mat4 {
        float4 { f / aspect, 0.0, 0.0, 0.0 },
        float4 { 0.0, f, 0.0, 0.0 },
        float4 { 0.0, 0.0, z, -1.0 },
        float4 { 0.0, 0.0, near * z, 0.0 },
    }
}

fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) -> mat4 {
    let w = right - left;
    let h = top - bottom;
    let d = near - far;
    mat4 {
        float4 { 2.0 / w, 0.0, 0.0, 0.0 },
        float4 { 0.0, 2.0 / h, 0.0, 0.0 },
        float4 { 0.0, 0.0, 1.0 / d, 0.0 },
        float4 { -(right + left) / w, -(top + bottom) / h, near / d, 1.0 },
    }
}

fn look_at(eye: float3, target: float3, up: float3) -> mat4 {
    let z = normalize(eye - target);
    let x = normalize(cross(up, z));
    let y = cross(z, x);
    mat4 {
        float4 { x.x, y.x, z.x, 0.0 },
        float4 { x.y, y.y, z.y, 0.0 },
        float4 { x.z, y.z, z.z, 0.0 },
        float4 { -dot(x, eye), -dot(y, eye), -dot(z, eye), 1.0 },
    }
}

extern fn detail::open(title: const u8[:], width: i64, height: i64, flags: i64, headless: bool) -> bool = "gs_gfx_open";
extern fn close() = "gs_gfx_close";
extern fn frame() -> bool = "gs_gfx_frame";
extern fn quit() = "gs_gfx_quit";
extern fn flush() = "gs_gfx_flush";
extern fn detail::error(out: u8[>..]&) = "gs_gfx_error";
extern fn detail::driver(out: u8[>..]&) = "gs_gfx_driver";
extern fn set_title(title: const u8[:]) = "gs_gfx_set_title";
extern fn detail::screen() -> u32 = "gs_gfx_screen";
extern fn detail::screen_depth() -> u32 = "gs_gfx_screen_depth";
extern fn detail::screen_size(out: int2&) = "gs_gfx_screen_size";
extern fn pixel_density() -> f32 = "gs_gfx_pixel_density";
extern fn display_scale() -> f32 = "gs_gfx_display_scale";
extern fn time() -> f64 = "gs_gfx_time";
extern fn delta_time() -> f64 = "gs_gfx_delta_time";
extern fn frame_count() -> i64 = "gs_gfx_frame_count";

fn open(title: const u8[:], width: i64, height: i64, flags: i64 = 0) -> bool {
    detail::open(title, width, height, flags, false)
}
fn open_headless(width: i64, height: i64, flags: i64 = 0) -> bool {
    detail::open("", width, height, flags, true)
}
fn error() -> u8[>..] {
    var out: u8[>..] = [];
    detail::error(out);
    return out;
}
fn driver() -> u8[>..] {
    var out: u8[>..] = [];
    detail::driver(out);
    return out;
}
fn screen() -> Texture { Texture { detail::screen() } }
fn screen_depth() -> Texture { Texture { detail::screen_depth() } }
fn screen_size() -> int2 {
    var out = int2_0;
    detail::screen_size(out);
    return out;
}

extern fn key_down(name: const u8[:]) -> bool = "gs_gfx_key_down";
extern fn key_pressed(name: const u8[:]) -> bool = "gs_gfx_key_pressed";
extern fn key_released(name: const u8[:]) -> bool = "gs_gfx_key_released";
extern fn mouse_down(button: i64) -> bool = "gs_gfx_mouse_down";
extern fn mouse_pressed(button: i64) -> bool = "gs_gfx_mouse_pressed";
extern fn mouse_released(button: i64) -> bool = "gs_gfx_mouse_released";
extern fn detail::mouse_pos(out: float2&) = "gs_gfx_mouse_pos";
extern fn detail::mouse_delta(out: float2&) = "gs_gfx_mouse_delta";
extern fn mouse_wheel() -> f32 = "gs_gfx_mouse_wheel";
extern fn mouse_in_window() -> bool = "gs_gfx_mouse_in_window";
extern fn focused() -> bool = "gs_gfx_focused";
extern fn set_mouse_relative(on: bool) -> bool = "gs_gfx_set_mouse_relative";
extern fn mouse_relative() -> bool = "gs_gfx_mouse_relative";
extern fn detail::event_count() -> i64 = "gs_gfx_event_count";
extern fn detail::event_at(index: i64, out: gfx::Event&) = "gs_gfx_event_at";
extern fn text_input(on: bool) = "gs_gfx_text_input";
extern fn detail::clipboard(out: u8[>..]&) = "gs_gfx_clipboard";
extern fn set_clipboard(text: const u8[:]) -> bool = "gs_gfx_set_clipboard";
extern fn inject_key(name: const u8[:], down: bool) -> bool = "gs_gfx_inject_key";
extern fn inject_mouse(x: f32, y: f32, button: i64, down: bool) = "gs_gfx_inject_mouse";
extern fn inject_text(text: const u8[:]) -> bool = "gs_gfx_inject_text";
extern fn inject_focus(focused: bool) -> bool = "gs_gfx_inject_focus";

fn mouse_pos() -> float2 {
    var out = float2_0;
    detail::mouse_pos(out);
    return out;
}
fn mouse_delta() -> float2 {
    var out = float2_0;
    detail::mouse_delta(out);
    return out;
}
fn events() -> Event[>..] {
    var out: Event[>..] = [];
    for i in detail::event_count() {
        var event = Event { .. };
        detail::event_at(i, event);
        out.push(event);
    }
    return out;
}
fn clipboard() -> u8[>..] {
    var out: u8[>..] = [];
    detail::clipboard(out);
    return out;
}

extern fn detail::buffer(usage: i64, size: i64, data: const u8[:]) -> u32 = "gs_gfx_buffer";
extern fn detail::update_buffer(id: u32, offset: i64, data: const u8[:]) -> bool = "gs_gfx_update_buffer";
extern fn detail::buffer_size(id: u32) -> i64 = "gs_gfx_buffer_size";
extern fn detail::release_buffer(id: u32) = "gs_gfx_release_buffer";

fn buffer(usage: i64, size: i64, data: const u8[:]) -> Buffer {
    Buffer { detail::buffer(usage, size, data) }
}
fn buffer(usage: i64, data: const u8[:]) -> Buffer { buffer(usage, data.len, data) }
fn vertex_buffer(data: const u8[:]) -> Buffer { buffer(BUFFER_VERTEX, data) }
fn index_buffer(data: const u8[:]) -> Buffer { buffer(BUFFER_INDEX, data) }
fn update_buffer(b: Buffer, offset: i64, data: const u8[:]) -> bool {
    detail::update_buffer(b.id, offset, data)
}
fn update_buffer(b: Buffer, data: const u8[:]) -> bool { update_buffer(b, 0, data) }
fn buffer_size(b: Buffer) -> i64 { detail::buffer_size(b.id) }
fn release(b: Buffer) { detail::release_buffer(b.id); }

extern fn detail::texture2d(width: i64, height: i64, format: i32, usage: i32) -> u32 = "gs_gfx_texture2d";
extern fn detail::update_texture(id: u32, data: const u8[:]) -> bool = "gs_gfx_update_texture";
extern fn detail::read_pixels(id: u32, out: u8[>..]&) = "gs_gfx_read_pixels";
extern fn screenshot(path: const u8[:]) -> bool = "gs_gfx_screenshot";
extern fn detail::release_texture(id: u32) = "gs_gfx_release_texture";
extern fn detail::sampler(filter: i32, wrap: i32, compare: i32) -> u32 = "gs_gfx_sampler";
extern fn detail::release_sampler(id: u32) = "gs_gfx_release_sampler";

fn texture2d(width: i64, height: i64, format: i32, usage: i32) -> Texture {
    Texture { detail::texture2d(width, height, format, usage) }
}
fn texture2d(width: i64, height: i64) -> Texture { texture2d(width, height, RGBA8, SAMPLED) }
fn depth_target(width: i64, height: i64) -> Texture {
    texture2d(width, height, DEPTH, SAMPLED | DEPTH_TARGET)
}
fn update_texture(t: Texture, data: const u8[:]) -> bool { detail::update_texture(t.id, data) }
fn read_pixels(t: Texture) -> u8[>..] {
    var out: u8[>..] = [];
    detail::read_pixels(t.id, out);
    return out;
}
fn release(t: Texture) { detail::release_texture(t.id); }
fn sampler(filter: i32, wrap: i32) -> Sampler { Sampler { detail::sampler(filter, wrap, 0) } }
fn shadow_sampler() -> Sampler { Sampler { detail::sampler(LINEAR, CLAMP, COMPARE_LESS_EQUAL) } }
fn release(s: Sampler) { detail::release_sampler(s.id); }

extern fn detail::pipeline(vs: const u8[:], fs: const u8[:], formats: const u8[:],
                           primitive: i32, cull: i32, clockwise: bool, wireframe: bool,
                           depth_test: bool, depth_write: bool, depth_compare: i32, blend: i32,
                           instance_location: i32, depth_bias: f32, depth_bias_slope: f32) -> u32 = "gs_gfx_pipeline";
extern fn detail::release_pipeline(id: u32) = "gs_gfx_release_pipeline";
extern fn detail::begin_pass(c0: u32, c1: u32, c2: u32, c3: u32,
                             r0: u32, r1: u32, r2: u32, r3: u32, depth: u32,
                             layer: i32, mip: i32, clear_color: bool, clear_depth: bool,
                             r: f32, g: f32, b: f32, a: f32, depth_value: f32) -> bool = "gs_gfx_begin_pass";
extern fn end_pass() = "gs_gfx_end_pass";
extern fn detail::bind(id: u32) = "gs_gfx_bind";
extern fn detail::bind_vertex_buffer(slot: i64, id: u32, offset: i64) = "gs_gfx_bind_vertex_buffer";
extern fn detail::bind_index_buffer(id: u32, index_size: i64, offset: i64) = "gs_gfx_bind_index_buffer";
extern fn detail::bind_texture(stage: i64, slot: i64, texture: u32, sampler: u32) = "gs_gfx_bind_texture";
extern fn push_uniforms(stage: i64, slot: i64, data: const u8[:]) = "gs_gfx_push_uniforms";
extern fn viewport(x: f32, y: f32, w: f32, h: f32) = "gs_gfx_viewport";
extern fn scissor(x: i64, y: i64, w: i64, h: i64) = "gs_gfx_scissor";
extern fn draw(vertices: i64) = "gs_gfx_draw";
extern fn draw_instanced(vertices: i64, instances: i64) = "gs_gfx_draw_instanced";
extern fn draw_indexed(indices: i64) = "gs_gfx_draw_indexed";
extern fn draw_indexed_instanced(indices: i64, instances: i64) = "gs_gfx_draw_indexed_instanced";

fn pipeline(vs: const u8[:], fs: const u8[:], desc: PipelineDesc) -> Pipeline {
    Pipeline { detail::pipeline(vs, fs, desc.formats, desc.primitive, desc.cull, desc.clockwise,
        desc.wireframe, desc.depth_test, desc.depth_write, desc.depth_compare, desc.blend,
        desc.instance_location, desc.depth_bias, desc.depth_bias_slope) }
}
fn pipeline(vs: const u8[:], fs: const u8[:]) -> Pipeline { pipeline(vs, fs, PipelineDesc { .. }) }
fn release(p: Pipeline) { detail::release_pipeline(p.id); }
fn begin_pass(desc: PassDesc) -> bool {
    detail::begin_pass(desc.color[0].id, desc.color[1].id, desc.color[2].id, desc.color[3].id,
        desc.resolve[0].id, desc.resolve[1].id, desc.resolve[2].id, desc.resolve[3].id, desc.depth.id,
        desc.layer, desc.mip, desc.clear_color, desc.clear_depth, desc.color_value.x,
        desc.color_value.y, desc.color_value.z, desc.color_value.w, desc.depth_value)
}
fn begin_pass(target: Texture, depth: Texture, clear: float4) -> bool {
    begin_pass(PassDesc { color: [target, Texture { 0 }, Texture { 0 }, Texture { 0 }],
                          depth: depth, color_value: clear })
}
fn begin_screen(clear: float4) -> bool { begin_pass(screen(), screen_depth(), clear) }
fn bind(p: Pipeline) { detail::bind(p.id); }
fn bind_vertex_buffer(slot: i64, b: Buffer, offset: i64) { detail::bind_vertex_buffer(slot, b.id, offset); }
fn bind_vertex_buffer(b: Buffer) { bind_vertex_buffer(0, b, 0); }
fn bind_index_buffer(b: Buffer, index_size: i64, offset: i64 = 0) {
    detail::bind_index_buffer(b.id, index_size, offset);
}
fn bind_texture(stage: i64, slot: i64, t: Texture, s: Sampler) {
    detail::bind_texture(stage, slot, t.id, s.id);
}
fn uniforms<T>(stage: i64, slot: i64, u: T) { push_uniforms(stage, slot, bytes_of([u])); }
