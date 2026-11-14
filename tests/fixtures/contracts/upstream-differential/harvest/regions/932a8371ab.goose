fn apply<F>(n: i64) -> i64[>..] { F([n, n + 1]) }
export fn tick(n: i64) -> i64 {
    let kept = apply(n) { xs: i64[>..] => xs.push(9); copy(xs) };
    for i in 100 {
        let value = apply(n + i) { xs: i64[>..] => xs[0] += 10; copy(xs) };
        if value.len != 2 || value[0] != n + i + 10 { abort("wrong owned callback result"); }
    }
    if kept.len != 3 || kept[0] != n || kept[2] != 9 { abort("callback result was released"); }
    return n + 1;
}
fn main() {}