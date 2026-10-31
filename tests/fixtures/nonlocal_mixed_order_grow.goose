recursive fn target(b: bool) -> i64, i64[>..], i64 {
    var values: i64[>..] = [1, 2];
    recursive fn leave(b: bool) { if b { return values.push(3), [7], 4 from target; } }
    leave(b); return 0, values, 0;
}
fn main() { var a, xs, b = target(true); print(a, " ", xs, " ", b); xs.push(8); print(xs, " ", xs.pop()); }
