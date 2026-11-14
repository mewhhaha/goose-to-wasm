
var neighbor: i64[>..] = [987654321];
recursive fn leave(depth: i64, value: i64) {
    if depth > 0 { leave(depth - 1, value); return; }
    return value + 1, [value + 2], value + 3 from target;
}
fn target(value: i64) -> i64, i64[>..], i64 { leave(3, value); return 0, [], 0; }
export fn tick(n: i64) -> i64 { let a, value, b = target(n); a }
fn main() {}