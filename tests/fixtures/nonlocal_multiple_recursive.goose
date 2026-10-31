recursive fn target(n: i64) -> i64[>..], i64[>..], i64 {
    if n > 0 { return target(n - 1); }
    recursive fn leave(n: i64) { return [n], [n + 1], n from target; }
    leave(n); return [], [], -1;
}
fn main() { var a, b, n = target(12); print(a," ",b," ",n); a.push(7); b.push(8); print(a," ",b); }
