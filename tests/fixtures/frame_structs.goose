extern fn bench_input() -> i64;
struct Packet { tag: u8, id: i64, values: i64[>..] }
struct Shrinking { id: i64, values: i64[>..<] }
var empty: Packet;
fn make(n: i64) -> Packet { return Packet { 1, n, [n + 1, n + 2] }; }
fn bump(packet: Packet&) -> i64 { packet.id += 10; packet.values[0] += 20; packet.values.push(99); return packet.id; }
fn aliases(n: i64) -> Packet, i64, Packet {
    var packet = make(n); return packet, bump(packet), packet;
}
fn changed(packet: Packet) -> Packet { packet.id += 100; packet.values.push(88); return packet; }
inline fn relay(n: i64) -> Packet { var packet = make(n); return packet; }
recursive fn forward(n: i64) -> Packet { if n <= 0 { return make(7); } return forward(n - 1); }
fn main() {
    let n = bench_input(); var packet = make(n); let copied = changed(copy(packet));
    print(empty.id, " ", empty.values.len, " ", packet.id, " ", packet.values, " ", copied.id, " ", copied.values);
    let a, count, b = aliases(n); print(a.id, " ", a.values, " ", count, " ", b.id, " ", b.values);
    packet = Packet { 2, n + 50, [60, 61] }; packet.values = [packet.id, 62];
    print(packet.tag, " ", packet.id, " ", packet.values);
    let broken: Packet = loop { var local = make(n + 70); local.values.push(77); break copy(local); };
    print(broken.id, " ", broken.values, " ", relay(n + 80).values[1], " ", forward(20).id);
    var shrinking = Shrinking { n, [1, 2] }; let popped = shrinking.values.pop();
    shrinking = Shrinking { n + 1, [3] }; print(popped, " ", shrinking.id, " ", shrinking.values);
}
