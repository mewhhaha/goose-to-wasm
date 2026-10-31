fn replace() -> i64 { return [7], 2, 3 from target; }
fn target() -> i64[>..], i64, i64 {
    recursive fn leave() { return [11], replace(), 1 from target; }
    leave(); return [], 0, 0;
}
fn main() { var xs, a, b = target(); print(xs," ",a," ",b); xs.push(8); print(xs," ",xs.pop()); }
