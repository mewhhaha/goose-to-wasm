fn bench_input() -> i64 { return 5; }
var target: u8[>..<] = [];
var calls = 0;
recursive fn produce(n: i64) -> u8[u8] {
    var xs: u8[>..] = []; xs.resize(bench_input() + n, 7); return xs;
}
recursive fn descend(n: i64) -> i64 {
    calls++; if n <= 0 { return 0; } return descend(n - 1) + 1;
}
export fn tick(n: i64) -> i64 {
    target.clear(); calls = 0;
    for i in 5 { target.append(produce(descend(i))); }
    if calls != 15 || target.len != 1290 || target[1289] != 7 { abort("bad element run"); }
    return n + 1;
}
fn main() {}