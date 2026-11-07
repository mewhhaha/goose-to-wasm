fn view<T>(xs: const T[:], ys: const T[:]) -> i64 { xs.len * 10 + ys.len }
fn some<T>(x: T?, y: T&) -> i64 { if x { 1 } else { 0 } }
fn main() { let a: u8[2] = [1, 2]; var value: u8 = 4; print(view([], a), " ", view(a, []), " ", some(null, value)); }
