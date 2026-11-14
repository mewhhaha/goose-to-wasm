recursive fn forward(n: i64) -> i64[>..], i64, i64[>..] {
    if n <= 0 { return [7], 8, [9]; } return forward(n - 1);
}
fn main() { let a, b, c = forward(100); print(a[0] + b + c[0]); }