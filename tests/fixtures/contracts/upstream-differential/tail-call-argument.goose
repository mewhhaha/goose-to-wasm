// A body's final expression moves only itself (§7.3): a by-value parameter
// passed to a named function inside it, here an operand's call, is not
// copied implicitly (§4.1).
fn count(a: i64[]) -> i64 { a.len }

fn once(a: i64[]) -> i64 { 1 + count(a) }

fn main() { print(once([1])); }
