// The rest of the runtime's support for upstream's std, math and os
// (75ad5bd3, 13712d6a, json's shortest digits, os.read_stdin's bound),
// declared as upstream's standard library declares them.
extern fn byte_swap16(x: u16) -> u16 = "gs_byte_swap16";
extern fn byte_swap32(x: u32) -> u32 = "gs_byte_swap32";
extern fn byte_swap64(x: u64) -> u64 = "gs_byte_swap64";
extern fn hypot(x: f64, y: f64) -> f64 = "gs_hypot";     extern fn hypot(x: f32, y: f32) -> f32 = "gs_hypotf";
extern fn cbrt(x: f64) -> f64 = "gs_cbrt";               extern fn cbrt(x: f32) -> f32 = "gs_cbrtf";
extern fn exp2(x: f64) -> f64 = "gs_exp2";               extern fn exp2(x: f32) -> f32 = "gs_exp2f";
extern fn expm1(x: f64) -> f64 = "gs_expm1";             extern fn expm1(x: f32) -> f32 = "gs_expm1f";
extern fn log1p(x: f64) -> f64 = "gs_log1p";             extern fn log1p(x: f32) -> f32 = "gs_log1pf";
extern fn sinh(x: f64) -> f64 = "gs_sinh";               extern fn sinh(x: f32) -> f32 = "gs_sinhf";
extern fn cosh(x: f64) -> f64 = "gs_cosh";               extern fn cosh(x: f32) -> f32 = "gs_coshf";
extern fn tanh(x: f64) -> f64 = "gs_tanh";               extern fn tanh(x: f32) -> f32 = "gs_tanhf";
extern fn shortest_digits(x: f64, out: u8[:], point: i64&) -> i64 = "gs_f64_digits";
extern fn read_stdin(out: u8[>..]&, max: i64) -> bool = "gs_os_read_stdin_max";
fn digits(x: f64) {
    var buf: u8[17] = [0; 17];
    var point = 0;
    let n = shortest_digits(x, buf[..], point);
    print(n, " ", buf[..n], " ", point);
}
fn main() {
    let h: u16 = 4660; let w: u32 = 305419896; let d: u64 = 81985529216486895;
    print(byte_swap16(h), " ", byte_swap32(w), " ", byte_swap64(d));
    let three: f32 = 3.0; let four: f32 = 4.0; let cube: f32 = 125.0; let zero: f32 = 0.0;
    print(hypot(3.0, 4.0), " ", hypot(three, four), " ", cbrt(64.0), " ", cbrt(cube), " ", exp2(10.0), " ", exp2(three));
    print(expm1(0.0), " ", log1p(0.0), " ", sinh(0.0), " ", cosh(0.0), " ", tanh(0.0), " ",
          expm1(zero), " ", log1p(zero), " ", sinh(zero), " ", cosh(zero), " ", tanh(zero));
    digits(0.1); digits(1234.5); digits(-0.00025); digits(0.0); digits(1.0e300);
    var text: u8[>..] = [];
    print(read_stdin(text, 5), " ", text);
    print(read_stdin(text, 100), " ", text);
    print(read_stdin(text, 100), " ", text.len);
}
