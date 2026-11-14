var neighbor: i64[>..] = [987654321];
fn mutate<F>(xs: i64[>..]&) { xs = [F(); 4294967296]; }
fn target(n: i64) -> i64 {
    var xs: i64[>..] = [9]; mutate(xs) { if n >= 0 { return n + 1; } 4 }; return 0;
}
export fn tick(n: i64) -> i64 { target(n) }
fn main() {}