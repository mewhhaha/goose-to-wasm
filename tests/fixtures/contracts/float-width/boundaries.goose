fn bits(x: f64) -> u64 { var one: f64[1] = [x]; let bytes = bytes_of(one); var value: u64 = 0; for byte, i in bytes { value |= (byte as u64) << (i * 8); } value }
fn emit(label: const u8[:], x: f64) { print(label, " ", bits(x)); }
const GNEG: f32 = -0.0;
const GPOS: f32 = 0.1;
fn main() {
 let p0: f32 = 0.0; emit("positive_zero", p0);
 let p1: f32 = -0.0; emit("negative_zero", p1);
 let p2: f32 = 0.1; emit("positive_tenth", p2);
 let p3: f32 = -0.1; emit("negative_tenth", p3);
 let p4: f32 = 1.401298464324817e-45; emit("min_subnormal", p4);
 let p5: f32 = -1.401298464324817e-45; emit("negative_min_subnormal", p5);
 let p6: f32 = 7.006492321624085e-46; emit("half_min_subnormal", p6);
 let p7: f32 = -7.006492321624085e-46; emit("negative_half_min_subnormal", p7);
 let p8: f32 = 1.1754943508222875e-38; emit("min_normal", p8);
 let p9: f32 = 3.4028234663852886e+38; emit("max_finite", p9);
 let p10: f32 = -3.4028234663852886e+38; emit("negative_max_finite", p10);
 let p11: f32 = 3.5e+38; emit("overflow", p11);
 let p12: f32 = -3.5e+38; emit("negative_overflow", p12);
 let p13: f32 = 1.0000000596046448; emit("tie_even", p13);
 let p14: f32 = 1.0000001788139343; emit("tie_odd", p14);
 var cq: const f32 = -0.0; emit("qualified_zero", cq);
 const cp: f32 = 0.1; let widened: f64 = cp; emit("qualified_tenth", widened);
 emit("global_zero", GNEG); emit("global_tenth", GPOS);
 let wide = 3.5e38; emit("unfitted_wide", wide);
 let plain = 0.1; emit("unfitted_tenth", plain);
 var n: i32 = 9; let unfitted = n * 0.1; emit("unfitted_computation", unfitted);
 let fitted: f32 = n * 0.1; emit("fitted_computation", fitted);
}
