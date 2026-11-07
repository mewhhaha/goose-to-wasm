fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn show(xs: u8[2]) { let first: i64 = xs[0]; let last: i64 = xs[1]; print(first, " ", last); }
var calls: i64 = 0;
fn first_condition() -> bool { calls = calls * 10 + 1; true }
fn last_value() -> u8 { calls = calls * 10 + 2; 9 }
fn main() { let result = pair(if first_condition() { [1, 2] } else { [3, 4] }, last_value()); let first: i64 = result[0]; let last: i64 = result[1]; print(first, " ", last, " ", calls); }
