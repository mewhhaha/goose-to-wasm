var drops: i64 = 0;
fn debris(n: i64) -> i64[], i64, i64[2], i64[>..<] {
    drops += 1;
    return [n], n + 1, [n + 2, n + 3], [n + 4];
}
recursive fn descend(n: i64) -> i64 {
    if n == 0 { return 0; }
    debris(n);
    return descend(n - 1) + 1;
}
fn main() {
    var total: i64 = 0;
    for i in 0..1000 { total += descend(8); }
    print(total, " ", drops);
}
