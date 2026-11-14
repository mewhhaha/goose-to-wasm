// A recursive call whose several results, one or more of them owning
// storage, are forwarded by `return f(n - 1)` builds each result where its
// caller receives it, so the call keeps no data region of its own frame.
recursive fn pair(n: i64) -> i64[>..], i64 {
    if n <= 0 { return [7], 8; } return pair(n - 1);
}
recursive fn swapped(n: i64) -> i64, i64[>..] {
    if n <= 0 { return 8, [7]; } return swapped(n - 1);
}
recursive fn triple(n: i64) -> i64[>..], i64, i64[>..] {
    if n <= 0 { return [7], 8, [9]; } return triple(n - 1);
}
recursive fn branches(n: i64) -> i64[>..], i64 {
    if n <= 0 { return [n + 7], 8; }
    if n % 2 == 0 { return branches(n - 1); }
    return branches(n - 2);
}
fn main() {
    let a, b = pair(100); print(a[0] + b);
    let c, d = swapped(100); print(c + d[0]);
    let e, f, g = triple(100); print(e[0] + f + g[0]);
    let h, i = branches(100); print(h[0] + i);
}
