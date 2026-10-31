extern fn bench_input() -> i64;
enum Leaf<T> { Data { code: u8, values: T[u8] } }
struct Inner<T> { id: i64, leaf: Leaf<T>.Data }
enum Event<T> { Empty, Data { tag: u16, inner: Inner<T> } }
fn prefix() -> i64 { print("prefix"); return 42; }
fn bytes(n: i64) -> u8[u64] { print("tail"); var values: u8[>..] = []; values.resize(n, 7); return values; }
fn make(n: i64) -> Event<u8>.. { return Event<u8>.Data { 3, Inner<u8> { prefix(), Leaf<u8>.Data { 4, bytes(n) } } }; }
fn main() { let e = make(bench_input()); match e { Data p => print(p.tag, " ", p.inner.id, " ", p.inner.leaf.code, " ", p.inner.leaf.values.len, " ", p.inner.leaf.values[0]), _ => {} } }
