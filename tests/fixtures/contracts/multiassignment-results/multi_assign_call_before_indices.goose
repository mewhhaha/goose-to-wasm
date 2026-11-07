var index = 0;
fn values() -> i64, i64 { index = 1; return 7, 8; }
fn main() { var xs = [0, 0, 0]; xs[index], xs[index + 1] = values(); print(xs); }
