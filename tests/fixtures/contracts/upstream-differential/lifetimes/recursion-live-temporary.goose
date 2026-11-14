// A statement temporary lives to the end of its statement, so a recursive
// call later in the same statement would keep its data region (§7.8).
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
recursive fn total(n: i64) -> i64 {
    if n <= 0 { return 0; } return make(n).len + total(n - 1);
}
fn main() { print(total(50)); }
