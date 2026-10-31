extern fn bench_input() -> i64;
recursive fn target(depth: i64) -> i64 {
    recursive fn leave() { return depth + 10 from target; }
    if depth > 0 { let child = target(depth - 1); print(child); }
    leave(); -1
}
fn pairs(n: i64) -> i64[2], i64 {
    var a = [n, n + 1];
    recursive fn leave() { return a, block { a[0] += 100; 9 } from pairs; }
    leave(); return [0, 0], 0;
}
enum Choice { A, B }
fn routed(n: i64) -> i64 {
    fn route(c: Choice.A) { return n + 40 from routed; }
    fn route(c: Choice.B) {}
    let choice: Choice = if n == 0 { Choice.A } else { Choice.B };
    route(choice); -1
}
fn invoke<F>(values: i64[>..]) { F(copy(values)); }
fn owned_scope(n: i64) -> i64 {
    var values: i64[>..] = [n];
    invoke(copy(values)) { xs: i64[>..] => return xs[0] + 60; };
    -1
}
fn scratch_scope(n: i64) -> i64 {
    recursive fn leave() -> i64 { return n + 70 from scratch_scope; }
    print("before:", leave(), "after"); -1
}
fn main() {
    let n = bench_input(); print(target(n));
    let a, b = pairs(n); print(a, " ", b);
    print(routed(n)); print(owned_scope(n)); print(scratch_scope(n));
}
