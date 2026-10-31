extern fn bench_input() -> i64;
fn invalid() -> i64[..] { print("cap"); return [..-1]; }
fn main() {
    let mode = bench_input();
    if mode == 0 { let xs: i64[..] = [..-1]; print(xs); }
    if mode == 1 { let xs: i64[..] = [..4294967296]; print(xs); }
    if mode == 2 { var xs: i64[..] = [..0]; xs.push(1); }
    var xs: i64[..] = [1, 2];
    if mode == 3 { xs.push(3); }
    if mode == 4 { xs.append([3]); }
    if mode == 5 { xs.resize(3, 0); }
    if mode == 6 { xs = [3, 4, 5]; }
    if mode == 7 { xs.clear(); xs.pop(); }
    if mode == 8 { xs.clear(); xs.resize(1); }
    if mode == 9 { xs.pop_n(-1); }
    if mode == 10 { xs.resize(-1); }
    if mode == 11 { let ys: i64[>..] = invalid(); print(ys); }
    print("unexpected success");
}
