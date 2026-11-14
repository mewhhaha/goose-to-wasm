recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
recursive fn total(n: i64) -> i64 {
    if n <= 0 { return 0; } let value = make(n).len; return total(n - 1) + value;
}
export fn tick(n: i64) -> i64 { if total(50) != 100 { abort("bad recursion"); } return n + 1; }
fn main() {}