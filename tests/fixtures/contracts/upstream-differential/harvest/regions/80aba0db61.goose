struct Frame { id: i64, values: i64[>..] }
var neighbor: i64[>..] = [987654321];
recursive fn leave(depth: i64, value: i64) {
    if depth > 0 { leave(depth - 1, value); return; }
    return value + 1, [value + 2], Frame { 7, [value + 3] } from target;
}
recursive fn target(depth: i64, value: i64) -> i64, i64[>..], Frame {
    if depth > 0 { return target(depth - 1, value); }
    leave(3, value); return 0, [], Frame { 0, [] };
}
export fn tick(n: i64) -> i64 { let a, left, right = target(12, n); a }
fn main() {}