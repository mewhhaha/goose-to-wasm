extern fn bench_input() -> i64;
recursive fn produce(n: i64) -> u8[u8] {
    print("body"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
inline fn inlined(n: i64) -> u8[u8] {
    print("inline"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
recursive fn mixed(n: i64) -> u8[u8], i64 {
    print("mixed"); var xs: u8[>..] = []; xs.resize(n, 7); return xs, 3;
}
recursive fn mixed_wide(n: i64) -> u8[], i64 { return mixed(n); }
recursive fn forward(n: i64, depth: i64) -> u8[u8] {
    if depth <= 0 { return produce(n); } return forward(n, depth - 1);
}
recursive fn local(n: i64) -> u8[u8] {
    print("local"); var xs: u8[>..] = []; xs.resize(n, 7);
    let checked: u8[u8] = xs[..]; return checked;
}
inline fn inline_local(n: i64) -> u8[u8] {
    print("inline-local"); var xs: u8[>..] = []; xs.resize(n, 7);
    let checked: u8[u8] = xs[..]; return checked;
}
fn size(xs: const u8[:]) -> i64 { return xs.len; }
fn main() {
    let mode = bench_input(); let n = bench_input();
    if mode == 0 { let xs = produce(n); print(xs.len); }
    if mode == 1 { let xs: u8[] = produce(n); print(xs.len); }
    if mode == 2 { let xs: u8[>..] = produce(n); print(xs.len); }
    if mode == 3 { var xs: u8[>..] = []; xs.append(produce(n)); print(xs.len); }
    if mode == 4 { let xs: u8[..] = produce(n); print(xs.len); }
    if mode == 5 { let xs: u8[..300] = produce(n); print(xs.len); }
    if mode == 6 { print(size(produce(n))); }
    if mode == 7 { let xs, value = mixed_wide(n); print(xs.len, " ", value); }
    if mode == 8 { let xs: u8[] = forward(n, 3); print(xs.len); }
    if mode == 9 { let xs: u8[] = local(n); print(xs.len); }
    if mode == 10 { let xs: u8[] = inlined(n); print(xs.len); }
    if mode == 11 { let xs: u8[>..] = inlined(n); print(xs.len); }
    if mode == 12 { let xs: u8[..] = inlined(n); print(xs.len, " ", xs.cap); }
    if mode == 13 { let xs: u8[..300] = inlined(n); print(xs.len); }
    if mode == 14 { inlined(n); print("done"); }
    if mode == 15 { print(size(inlined(n))); }
    if mode == 16 { let xs: u8[] = inline_local(n); print(xs.len); }
    if mode == 17 { var xs: u8[>..] = []; xs.append(inlined(n)); print(xs.len); }
    if mode == 18 { var xs: u8[>..] = []; xs.append(if n > 0 { produce(n) } else { produce(0) }); print(xs.len); }
    if mode == 19 { var xs: u8[>..] = []; xs.append(loop { break produce(n); }); print(xs.len); }
    if mode == 20 { let source: u8[>..] = inlined(n); var xs: u8[>..] = []; xs.append(copy(source)); print(xs.len); }
}
