fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn show(xs: u8[2]) { let first: i64 = xs[0]; let last: i64 = xs[1]; print(first, " ", last); }
fn nested<T>(a: T[2][2], b: T) -> T { a[1][0] + b }
fn main() { var b: u8 = 200; show(pair([1, 2], b)); show(reversed(b, [1, 2])); var n: u8 = 10; let sum: i64 = nested([[1, 2], [3, 4]], n); print(sum); show(pair([7; 2], n)); }
