var g: i64[2] = [1, 2];
var h: i64[2] = [3, 4];
var effects: i64 = 0;
fn reset() { g = [1, 2]; h = [3, 4]; }
fn change() -> i64 { effects += 1; g = [8, 9]; 0 }
fn head(xs: const i64[:], ignored: i64) -> i64 { xs[0] }
fn write(xs: i64[2]&) { xs[0] += 10; }
fn main() { write(if true { g } else { h }); print(g[0], " ", h[0]); }
