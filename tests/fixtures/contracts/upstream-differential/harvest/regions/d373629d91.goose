var neighbor: i64[>..] = [987654321];
recursive fn leave(depth: i64, value: i64) {
    if depth > 0 { leave(depth - 1, value); return; }
    return [value + 1] from target;
}
fn target(value: i64) -> i64[>..] { leave(3, value); return []; }
export fn tick(n: i64) -> i64 { var result = target(n); result[0] }
fn main() {}