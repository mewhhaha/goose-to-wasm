var saved: i64[>..] = [9];
let view: const i64[:] = saved[..];
var order: i64 = 0;
fn bump(value: i64) -> i64 { order = order * 10 + value; saved[0] += value; return value; }
fn receive(first: i64, earlier: i64, target: i64&, last: i64) -> i64[], i64&, i64[] {
    target += first + earlier + last;
    return [first], target, [last];
}
fn churn() -> i64[], i64[] { return [100, 101], [200, 201]; }
fn main() {
    receive(bump(1), saved[0], saved[0], bump(2));
    for i in 0..10000 { churn(); }
    print(order, " ", saved[0], " ", view[0]);
}
