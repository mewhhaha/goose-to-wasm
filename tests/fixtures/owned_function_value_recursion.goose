extern fn bench_input() -> i64;
fn apply<F>(n: i64) -> i64[u8] { F(n) }
recursive fn descend(n: i64) -> i64[u8] {
    if n <= 0 { return [7, 8]; }
    return apply(n - 1) { x => descend(x) };
}
fn main() {
    let n = bench_input(); let xs = descend(n); print(xs);
    let grown: i64[>..] = descend(n); print(grown);
}
