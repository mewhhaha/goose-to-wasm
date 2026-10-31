extern fn bench_input() -> i64;
struct Packet { id: i64, values: i64[..] }
fn make(n: i64) -> Packet {
    var packet = Packet { n, [..n + 4] }; packet.values.push(n); return packet;
}
fn bump(packet: Packet&) -> i64 { packet.id += 10; packet.values.push(99); return packet.values.len; }
fn aliases(n: i64) -> Packet, i64, Packet {
    var packet = make(n); return packet, bump(packet), packet;
}
fn changed(packet: Packet) -> Packet { packet.id += 100; packet.values.push(88); return packet; }
fn interrupted(packet: Packet&, n: i64) {
    packet.values = [1, if n > 0 { return; } else { 2 }];
}
fn main() {
    let n = bench_input(); var original = make(n); let copied = copy(original); copied.values.push(7);
    print(original.id, " ", original.values, " ", original.values.cap, " ", copied.values, " ", copied.values.cap);
    original.values = original.values[..]; original.values.resize(3, 8);
    print(original.values, " ", original.values.cap);
    interrupted(original, 1); print(original.values, " ", original.values.cap);
    let a, count, b = aliases(n); b.values.clear();
    print(a.id, " ", a.values, " ", a.values.cap, " ", count, " ", b.id, " ", b.values.len, " ", b.values.cap);
    let modified = changed(copy(original)); print(original.id, " ", original.values.len, " ", modified.id, " ", modified.values, " ", modified.values.cap);
}
