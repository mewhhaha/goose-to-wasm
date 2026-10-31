recursive fn produce(value: i64) -> i64[] { return [7]; }
recursive fn invoke<F>(b: bool) { if b { F(); } }
fn target(b: bool) -> i64[>..] { var xs: i64[>..] = [1, 2]; invoke(b) { return produce(xs.push(3)); } return xs; }
fn main() { var xs = target(true); print(xs); xs.push(8); print(xs," ",xs.pop()); }
