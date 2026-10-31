extern fn bench_input() -> i64;
recursive fn make(n: i64) -> u8[u8] {
    print("make"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
fn apply<F>() -> u8[>..] { F() }
fn append<F>() -> i64 { var xs: u8[>..] = []; xs.append(F()); xs.len }
fn main() {
    let mode = bench_input(); let n = bench_input();
    if mode == 0 { print(apply() { make(n) }.len); }
    if mode == 1 { print(append() { make(n) }); }
    if mode == 2 { let xs: u8[..300] = block { apply() { make(n) } }; print(xs.len); }
}
