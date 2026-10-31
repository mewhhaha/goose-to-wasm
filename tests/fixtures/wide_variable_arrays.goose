extern fn bench_input() -> i64;
recursive fn produce16(n: i64) -> u8[u16] {
    print("16"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
recursive fn produce64(n: i64) -> u8[u64] {
    print("64"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
fn later() -> i64 { print("later"); return 42; }
recursive fn mixed16(n: i64) -> u8[u16], i64 {
    print("mixed16"); var xs: u8[>..] = []; xs.resize(n, 7); return xs, later();
}
recursive fn narrow(n: i64) -> u8[u8], i64 { return mixed16(n); }
fn size(xs: const u8[:]) -> i64 { return xs.len; }
recursive fn take(xs: u8[u8]) -> i64 { print("take"); return xs.len; }
recursive fn echo(xs: u8[u8]) -> u8[u8] { print("echo"); return xs; }
inline fn echo_inline(xs: u8[u8]) -> u8[u8] { print("echo-inline"); return xs; }
struct Pair { x: i64, y: i64 }
recursive fn pairs(n: i64) -> Pair[u8] {
    print("pairs"); var xs: Pair[>..] = []; xs.resize(n, Pair { 7, 8 }); return xs;
}
recursive fn grown(n: i64) -> u8[>..] {
    print("grow"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
recursive fn mixed_grow(n: i64) -> u8[>..], i64 {
    print("grow-mixed"); var xs: u8[>..] = []; xs.resize(n, 7); return xs, later();
}
recursive fn narrow_grow(n: i64) -> u8[u8], i64 { return mixed_grow(n); }
recursive fn second(n: i64) -> i64, u8[>..] {
    print("second"); var xs: u8[>..] = []; xs.resize(n, 7); return later(), xs;
}
recursive fn narrow_second(n: i64) -> i64, u8[u8] { return second(n); }
fn main() {
    let mode = bench_input(); let n = bench_input();
    if mode == 0 { let xs = produce16(n); print(xs.len); }
    if mode == 1 { let xs: u8[] = produce16(n); print(xs.len); }
    if mode == 2 { let xs: u8[>..] = produce16(n); print(xs.len); }
    if mode == 3 { print(size(produce16(n))); }
    if mode == 4 { let xs: u8[u8] = produce16(n); print(xs.len); }
    if mode == 5 { let xs = produce64(n); print(xs.len); }
    if mode == 6 { let xs: u8[u16] = produce64(n); print(xs.len); }
    if mode == 7 { let xs: u8[] = produce64(n); print(xs.len); }
    if mode == 8 { let xs, value = narrow(n); print(xs.len, " ", value); }
    if mode == 9 { print(take(produce16(n))); }
    if mode == 10 { let xs: u8[] = echo(produce16(n)); print(xs.len); }
    if mode == 11 { let xs: u8[] = echo_inline(produce16(n)); print(xs.len); }
    if mode == 12 { let xs: Pair[] = pairs(n); print(xs.len, " ", xs[n - 1].x); }
    if mode == 13 { let xs = pairs(n); print(xs.len, " ", xs[n - 1].x); }
    if mode == 14 { let xs: u8[u8] = grown(n); print(xs.len); }
    if mode == 15 { let xs, value = narrow_grow(n); print(xs.len, " ", value); }
    if mode == 16 { let value, xs = narrow_second(n); print(value, " ", xs.len); }
}
