var trace = 0;
fn pair() -> i64, i64 { trace = 1; return 7, 8; }
fn index(n: i64) -> i64 { trace = trace * 10 + n; n - 2 }
fn main() { var xs = [0, 0]; xs[index(2)], xs[index(3)] = pair(); print(trace, " ", xs); }
