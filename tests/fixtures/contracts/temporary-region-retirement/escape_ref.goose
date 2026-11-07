fn make() -> i64[2] { [4, 5] }
fn main() { var out: const i64? = null; for &x in make() { out = x; } if out { print(out); } }
