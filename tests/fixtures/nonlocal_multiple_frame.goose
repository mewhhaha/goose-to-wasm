struct Frame { id: i64, values: i64[>..] }
recursive fn target(flag: bool) -> i64, i64[>..], Frame {
    var left: i64[>..] = [1, 2]; var right: Frame = Frame { 2, [10, 20] };
    recursive fn leave(flag: bool) { if flag { return left.push(3) + right.values.push(30), [7], Frame { 9, [40] } from target; } }
    leave(flag); return 0, left, right;
}
fn main() { var n, a, b = target(true); print(n," ",a," ",b.id, " ", b.values); a.push(8); b.values.push(50); print(a," ",a.pop()," ",b.values," ",b.values.pop()); }
