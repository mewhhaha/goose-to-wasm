extern fn bench_input() -> i64;
struct Packet { tag: u8, id: i64, values: i64[] }
var empty: Packet;
fn make(n: i64) -> Packet { return Packet { 1, n, [n + 1, n + 2] }; }
fn bump(packet: Packet&) -> i64 { packet.id += 10; packet.values[0] += 20; return packet.id; }
fn aliases(n: i64) -> Packet, i64, Packet {
    var packet = make(n); return packet, bump(packet), packet;
}
fn changed(packet: Packet) -> Packet { packet.id += 100; packet.values[0] += 200; return packet; }
recursive fn forward(n: i64) -> Packet {
    if n <= 0 { return make(7); } return forward(n - 1);
}
fn main() {
    let n = bench_input(); let original = make(n); let copied = changed(copy(original));
    print(empty.tag, " ", empty.id, " ", empty.values.len);
    print(original.id, " ", original.values, " ", copied.id, " ", copied.values);
    let a, count, b = aliases(n); print(a.id, " ", a.values, " ", count, " ", b.id, " ", b.values);
    let selected: Packet = if n > 0 { make(30) } else { make(40) };
    let broken: Packet = loop { let local = make(50); break copy(local); };
    print(selected.id, " ", selected.values, " ", broken.id, " ", broken.values);
    print(forward(20).values[0]);
}
