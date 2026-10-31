extern fn bench_input() -> i64;
struct Leaf { id: i64, values: u8[u8] }
struct Outer { tag: u8, leaf: Leaf }
fn prefix(n: i64) -> i64 { print("prefix"); return n; }
fn bytes(n: i64) -> u8[u64] { print("tail"); var values: u8[>..] = []; values.resize(n, 7); return values; }
fn make(n: i64) -> Outer { return Outer { 3, Leaf { prefix(42), bytes(n) } }; }
fn main() { let p = make(bench_input()); print(p.tag, " ", p.leaf.id, " ", p.leaf.values.len, " ", p.leaf.values[0]); }
