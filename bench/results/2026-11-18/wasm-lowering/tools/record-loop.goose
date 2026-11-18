struct Packet { values: i64[16] }

recursive fn update(var packet: Packet, index: i64) -> i64 {
    packet.values[0] += index;
    return packet.values[0] + packet.values[15];
}

fn main() {
    let packet = Packet { [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16] };
    var total: i64 = 0;
    for i in 2000000 { total += update(packet, i); }
    print(total, " ", packet.values[0]);
}
