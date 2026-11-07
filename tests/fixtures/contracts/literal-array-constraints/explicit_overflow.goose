fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn main() { let result = pair<u8>([300, 2], 1); print(result); }
