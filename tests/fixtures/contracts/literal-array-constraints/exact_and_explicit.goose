fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn reversed<T>(b: T, a: T[2]) -> T[2] { [a[1], b] }
fn rank(xs: i64[2]) -> i64 { 64 }
fn rank(xs: u8[2]) -> i64 { 8 }
fn main() { var small: u8 = 3; print(rank([1, 2]), " ", rank(pair([1, 2], small)), " ", rank(pair<i64>([1, 2], small))); }
