extern fn bench_input() -> i64;
fn main() {
    let mode = bench_input();
    var a: i64[..2] = [1, 2];
    if mode == 0 { a.push(3); }
    if mode == 1 { a.append([3]); }
    if mode == 2 { a.resize(3, 0); }
    if mode == 3 { a.resize(-1); }
    if mode == 4 { a.pop_n(-1); }
    if mode == 5 { a.pop_n(3); }
    if mode == 6 { a.clear(); a.pop(); }
    if mode == 7 { a.clear(); a.resize(1); }
    if mode == 8 { let i = bench_input(); print(a[i]); }
    if mode == 9 { let i = bench_input(); print(a[..i + 1]); }
    if mode == 10 { let src: i64[3] = [1, 2, 3]; let s: const i64[:] = src; let b: i64[..2] = s; print(b); }
    print("unexpected success");
}
