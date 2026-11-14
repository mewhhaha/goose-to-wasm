// A non-fixed-size local in scope across a recursive call would keep its
// data region in every activation (§7.8).
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
recursive fn total(n: i64) -> i64 {
    if n <= 0 { return 0; } let v = make(n); return total(n - 1) + v.len;
}
fn main() { print(total(50)); }
