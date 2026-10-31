extern fn bench_input() -> i64;
recursive fn enable(n: i64) { if n > 0 { enable(n - 1); return; } return [99] from enabled; }
fn enabled() -> i64[>..] { enable(1); return []; }
struct F { id: i64, values: i64[>..] }
var g = F { 9, [7, 8, 9, 10] };
fn fill<C>() -> i64[>..] { return [C(); 16]; }
fn fill_argument(x: i64) -> i64[>..] { return [4]; }
fn make<C>(b: bool, mode: i64) -> F {
    var local = F { 2, [11, 12] };
    if b {
        if mode == 0 { return F { 7, fill() { C() } }; }
        return F { 7, fill_argument(C()) };
    }
    return local;
}
fn find(flag: bool, mode: i64) -> i64 { g = make(flag, mode) { if flag { return 7; } 4 }; 0 }
fn main() {
    let mode = bench_input();
    enabled();
    print(find(true, mode), " ", g.id, " ", g.values.len);
    if mode == 0 { print(g.values[0]); }
    else { g.values.push(10); print(g.values.len, " ", g.values[0]); }
}
