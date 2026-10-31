fn stop() -> i64 { return 9 from canceled; }
fn canceled() -> i64 { return 1, [11], stop() from target; }
fn target() -> i64, i64[>..], i64 { var values: i64[>..] = [1, 2]; print(canceled()); return 5, values, 6; }
fn main() { var a, xs, b = target(); print(a," ",xs," ",b); xs.push(7); print(xs," ",xs.pop()); }
