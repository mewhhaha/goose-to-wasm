reusable var pool: i64[>..] = [];
var values: i64[>..] = [10];
fn grow() -> i64 { values.push(20); return values.len; }
struct Packet { marker: i64 = grow() }
fn observe(n: i64 = grow()) { print(n); }
fn main() {
    pool.alloc_index(1);
    let old = values[..];
    let packet = Packet {};
    observe();
    print(packet.marker); print(old[0]); print(values.len); print(pool.len);
}
