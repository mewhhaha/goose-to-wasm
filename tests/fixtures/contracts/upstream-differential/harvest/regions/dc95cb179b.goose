fn target() -> i64[>..], i64[>..] {
    var right: i64[>..] = [987654321];
    recursive fn leave() { return [1; 15000], copy(right) from target; }
    leave(); return [], right;
}
fn main() { let left, right = target(); print(left.len, right.len); }