var calls: i64 = 0;
fn make() -> i64[2] { calls += 1; [4, 5] }
fn main() { var total: i64 = 0; for &x in make() { let alias: const i64& = x; if alias > 0 { let inner: const i64& = alias; total += inner; } } print(total, " ", calls); }
