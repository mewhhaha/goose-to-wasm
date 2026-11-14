fn bench_input() -> i64 { return 5; }
var values: i64[>..] = [9]; var neighbor: i64[>..] = [987654321];
recursive fn enable_leave() { return [1] from enable; }
fn enable() -> i64[>..] { enable_leave(); return []; }
fn make<F>() -> i64[] { return [F(); 1000000]; }
fn target() -> i64 { values = make() { if bench_input() >= 0 { return 7; } 4 }; return 0; }
fn main() { print(enable().len); print(target()); }