fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn show(xs: u8[2]) { let first: i64 = xs[0]; let last: i64 = xs[1]; print(first, " ", last); }
fn nested<T>(a: T[2][2], b: T) -> T[2] { [a[1][0], b] }
fn main() { var b: u8 = 200; let first: u8[2] = pair([1, 2], b); let last: u8[2] = reversed(b, [1, 2]); let grid: u8[2] = nested([[1, 2], [3, 4]], b); show(first); show(last); show(grid); }
