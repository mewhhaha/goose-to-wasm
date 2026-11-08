inline fn bad(n: i64) -> i64 {
    if n == 0 { return 0; }
    return bad(n - 1) + 1;
}
fn main() { print(bad(4)); }
