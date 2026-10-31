fn target() -> i64[>..], i64, i64[>..] {
    var values: i64[>..] = [1, 2];
    recursive fn leave() { return copy(values), block { values[0] = 9; 3 }, copy(values) from target; }
    leave(); return [], 0, [];
}
fn main() { var a, n, b = target(); print(a," ",n," ",b); a[0] = 77; print(a," ",b); }
