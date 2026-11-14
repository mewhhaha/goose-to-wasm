recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
fn bench_input() -> i64 { return 5; }
var values:i64[>..]=[9];
var neighbor:i64[>..]=[987654321];
fn create<F>()->i64[] { return [F();1000000]; }
fn target()->i64 {
    values=create() { if bench_input()>=0 { return 7; } 4 };
    return 0;
}
fn main() { print(enable().len); print(target()); }
