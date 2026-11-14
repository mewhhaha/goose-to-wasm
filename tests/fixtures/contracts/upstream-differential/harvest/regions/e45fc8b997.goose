struct Packet { id: i64, values: i64[>..] }
recursive fn named(n: i64) -> Packet {
    var packet = Packet { 0, [1] };
    packet = Packet { 2, [if n >= 0 { return Packet { 7, [8] }; } else { 1 }; 1000000] };
    return packet;
}
recursive fn parameter(var packet: Packet, n: i64) -> Packet {
    packet = Packet { 2, [if n >= 0 { return Packet { 7, [8] }; } else { 1 }; 1000000] };
    return packet;
}
export fn tick(n: i64) -> i64 {
    let a = named(n); let b = parameter(Packet { 0, [1] }, n);
    if a.id != 7 || a.values.len != 1 || a.values[0] != 8 || b.id != 7 || b.values.len != 1 || b.values[0] != 8 { abort("bad early frame result"); }
    return n + 1;
}
fn main() {}