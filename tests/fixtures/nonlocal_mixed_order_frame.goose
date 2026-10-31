struct Frame { id: i64, values: i64[>..] }
recursive fn target(b: bool) -> i64, Frame, i64 {
    var values = Frame { 1, [1, 2] };
    recursive fn leave(b: bool) { if b { return values.values.push(3), Frame { 7, [9] }, 4 from target; } }
    leave(b); return 0, values, 0;
}
fn main() { var a, xs, b = target(true); print(a, " ", xs.id, " ", xs.values, " ", b); xs.values.push(8); print(xs.values, " ", xs.values.pop()); }
