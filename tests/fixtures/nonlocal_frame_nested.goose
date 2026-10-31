extern fn bench_input() -> i64;
struct Inner { id: i64, values: i64[>..] }
struct Outer { tag: u8, child: Inner }
var counter: i64 = 0;
fn next() -> i64 { counter++; counter }
recursive fn leave(n: i64) {
    if n > 0 { leave(n - 1); return; }
    return Outer { 7, Inner { next(), [next(), next()] } } from target;
}
fn target(n: i64) -> Outer {
    var local = Outer { 1, Inner { -1, [-1] } };
    leave(n);
    return local;
}
fn main() {
    var value = target(bench_input());
    print(value.tag, " ", value.child.id, " ", value.child.values, " ", counter);
    value.child.values.push(4);
    print(value.child.values);
}
