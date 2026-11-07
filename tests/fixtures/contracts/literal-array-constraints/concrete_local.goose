fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn main() { let concrete = 1; var b: u8 = 2; let result: u8[2] = pair([concrete, 2], b); print(result); }
