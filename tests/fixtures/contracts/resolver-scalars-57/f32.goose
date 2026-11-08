fn half(x: f32) -> f32 { var y: f32 = x; y += 1.0; y *= 0.5; return y; }
fn main() { var x: f32 = 16777216.0; x++; print(x as i64); print(half(3.0) as i64); var y: f64 = 1.5; y++; print(y); }
