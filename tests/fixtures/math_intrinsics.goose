import math;
import std;

extern fn bench_input() -> i64;
extern fn bench_input_f64() -> f64;
extern fn libm_sqrt(x: f64) -> f64 = "sqrt";
extern fn libm_sqrt(x: f32) -> f32 = "sqrtf";
extern fn libm_abs(x: f64) -> f64 = "fabs";
extern fn libm_abs(x: f32) -> f32 = "fabsf";

// A user body with an intrinsic's name must remain an ordinary function.
fn sqrt(x: i64) -> i64 { x + 100 }

fn main() {
    let wide = bench_input_f64();
    let narrow = wide as! f32;
    let bits = bench_input() as! u64;
    print(sqrt(wide), " ", libm_sqrt(wide), " ", floor(wide), " ",
          ceil(wide), " ", trunc(wide), " ", abs(wide), " ", libm_abs(wide));
    print(sqrt(narrow), " ", libm_sqrt(narrow), " ", floor(narrow), " ",
          ceil(narrow), " ", trunc(narrow), " ", abs(narrow), " ", libm_abs(narrow));
    // std.abs preserves -0.0; C fabs clears the sign bit. Keep both rules.
    print(1.0 / abs(wide), " ", 1.0 / libm_abs(wide));
    print(clz(bits), " ", sqrt(4 as i64));
}
