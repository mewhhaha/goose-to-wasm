fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn show(xs: u8[2]) { let first: i64 = xs[0]; let last: i64 = xs[1]; print(first, " ", last); }
fn main() { var b: u8 = 9; let condition = b > 0; show(pair(if condition { [1, 2] } else { [3, 4] }, b)); show(pair({ [5, 6] }, b)); show(pair(match b { 9 => [7, 8], _ => [1, 2] }, b)); }
