recursive fn pair(n: i64) -> i64, i64[>..], i64[>..] { return n, [7], [40]; }
recursive fn target(flag: bool) -> i64, i64[>..], i64[>..] {
    var left: i64[>..] = [1, 2]; var right: i64[>..] = [10, 20];
    recursive fn leave(flag: bool) { if flag { return pair(left.push(3) + right.push(30)) from target; } }
    leave(flag); return 0, left, right;
}
fn main() { var n, a, b = target(true); print(n," ",a," ",b); a.push(8); b.push(50); print(a," ",a.pop()," ",b," ",b.pop()); }
