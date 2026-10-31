fn target() -> i64[2], i64[>..], i64 {
    var fixed: i64[2] = [1, 2];
    recursive fn leave() { return fixed, [7], block { fixed[0] = 9; 3 } from target; }
    leave(); return fixed, [], 0;
}
fn main() { let a, xs, b = target(); print(a," ",xs," ",b); }
