fn mix(x: u32, y: i64) -> u64 { var z = x; z++; var q = y; q--; print(z as u64); print(q); return 18446744073709551615; }
fn main() { print(mix(4294967295, -9223372036854775807)); }
