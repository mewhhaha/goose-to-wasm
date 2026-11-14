struct Inner { id: i64, values: i64[>..] }
struct Frame { tag: u8, child: Inner }
var neighbor: i64[>..] = [987654321];
recursive fn leave(depth: i64, value: i64) {
    if depth > 0 { leave(depth - 1, value); return; }
    return Frame { 7, Inner { value + 1, [value + 2] } } from target;
}
fn target(value: i64) -> Frame { leave(3, value); return Frame { 0, Inner { 0, [] } }; }
export fn tick(n: i64) -> i64 { var result = target(n); result.child.id }
fn main() {}