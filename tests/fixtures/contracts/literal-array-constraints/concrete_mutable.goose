fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn ordinary(var value: i64) -> i64 { value += 1; value }
fn main() { var b: u8 = 2; let result: u8[2] = pair([ordinary(1), 2], b); print(result); }
