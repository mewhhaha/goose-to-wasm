// One growable receiving channel, reached through ordinary recursive frames.
extern fn bench_input() -> i64;
recursive fn leave(depth: i64, value: i64) {
    if depth > 0 { leave(depth - 1, value); return; }
    var source: i64[>..] = [value, value + 1];
    return source[..] from target;
}
fn target(value: i64) -> i64[>..] {
    var original: i64[>..] = [-1];
    leave(3, value);
    return original;
}
fn main() {
    let n = bench_input();
    var values = target(n);
    print(values);
    values.push(n + 2);
    print(values, " ", values.pop());
    print(target(n + 10));
}
