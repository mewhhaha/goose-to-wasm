extern fn bench_input() -> i64;
struct Pair { x: i64, y: i64 }
struct Envelope<T> { id: i64, values: T[] }
struct Defaults { tag: u8 = 7, id: i64 = 9, values: i64[] }
struct Packet { tag: u8, id: i64, values: i64[] }
struct Linked { point: i64&, values: i64[] }
var defaults: Defaults;
fn make(n: i64) -> Packet { return Packet { 1, n, [n + 1, n + 2] }; }
fn pair(n: i64) -> Envelope<Pair> { return Envelope<Pair> { n, [Pair { n + 1, n + 2 }] }; }
inline fn relay(n: i64) -> Packet { var packet = make(n); return packet; }
fn first(packet: const Packet&) -> const i64& { return packet.id; }
fn observe(packet: Packet) -> i64 { packet.id += 1; packet.values[0] += 10; return packet.id + packet.values[0]; }
fn external(packet: Linked) -> i64& { return packet.point; }
fn field(n: i64) -> i64 { print(n); return n; }
fn ordered() -> Packet { return Packet { tag: field(1) as u8, id: field(2), values: [field(3)] }; }
fn prefix_exit(n: i64) -> Packet {
    return Packet { 1, if n > 0 { return make(99); } else { 2 }, [3, 4] };
}
fn tail_exit(n: i64) -> Packet {
    return Packet { 1, 2, [3, if n > 0 { return make(88); } else { 4 }] };
}
fn main() {
    let n = bench_input(); print(defaults.tag, " ", defaults.id, " ", defaults.values.len);
    let a = pair(n); let b = copy(a); b.values[0].x += 10;
    print(a.id, " ", a.values[0].x, " ", b.values[0].x, " ", b.values[0].y);
    let sequence = relay(n); let kept: const i64& = first(sequence);
    print(first(sequence), " ", observe(make(n + 10)), " ", relay(n + 20).values[0]);
    var sum = 0; for value in sequence.values { sum += value; } print(sum);
    for value in make(n + 30).values { sum += value; } print(sum, " ", kept);
    let record = ordered(); print(record.tag, " ", record.id, " ", record.values[0]);
    let prefix = prefix_exit(n); let tail = tail_exit(n);
    print(prefix.id, " ", prefix.values, " ", tail.id, " ", tail.values);
    let chosen: Packet = match n { 0 => make(5), _ => make(6) }; print(chosen.id, " ", chosen.values);
    var number = n; let linked: const i64& = external(Linked { number, [1] }); number += 1000; print(linked);
}
