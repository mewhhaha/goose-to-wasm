fn build<F>(n: i64) -> i64[>..] { F(n) }
export fn tick(n: i64) -> i64 {
    let kept = build(n) { x => var local: i64[>..] = [x, x + 1]; copy(local) };
    for i in 100 {
        let other = build(n + i) { x => var local: i64[>..] = [x + 2]; copy(local) };
        if other[0] != n + i + 2 { abort("wrong callback local copy"); }
    }
    if kept[0] != n || kept[1] != n + 1 { abort("callback local escaped"); }
    return n + 1;
}
fn main() {}