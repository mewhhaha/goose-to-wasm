recursive fn enable(n: i64) { if n > 0 { enable(n - 1); return; } return [99] from enabled; }
fn enabled() -> i64[>..] { enable(1); return []; }
fn make(b: bool) -> i64[>..] {
    return block { break [1, if b { break [7]; } else { 2 }]; };
}
export fn tick(n: i64) -> i64 { var xs = make(n > 0); return xs[0]; }
fn main() { print(enabled()); print(tick(1)); print(tick(0)); }
