import std;
fn step(x: i64, y: u32) -> i64 { var total: i64 = x; var i: u32 = 0; while i < y { if i % 2 == 0 { total += 3; } else { total -= 1; } i++; } total--; total *= 2; return total; }
fn main() { print(step(10, 5)); }
