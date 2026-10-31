fn replace() -> i64 { return [7], [8], 9 from target; }
fn target() -> i64[>..], i64[>..], i64 {
    recursive fn leave() { return [11], [replace()], 4 from target; }
    leave(); return [], [], 0;
}
fn main() { var a, b, n = target(); print(a," ",b," ",n); a.push(70); b.push(80); print(a," ",b); }
