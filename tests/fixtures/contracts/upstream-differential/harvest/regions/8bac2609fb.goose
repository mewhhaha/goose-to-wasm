enum Choice { One, Two }
fn build(c: Choice.One, n: i64) -> i64[>..] { return [n, n + 1]; }
fn build(c: Choice.Two, n: i64) -> i64[>..] { return [n, n + 2]; }
export fn tick(n: i64) -> i64 {
    let choice: Choice = if n % 2 == 0 { Choice.One } else { Choice.Two };
    let kept = build(choice, n);
    for i in 100 {
        let other = build(choice, n + i);
        if other.len != 2 || other[0] != n + i { abort("wrong dispatch result"); }
    }
    if kept[0] != n || kept.len != 2 { abort("dispatch result released"); }
    return n + 1;
}
fn main() {}