struct Packet { bytes: u8[1200000], tag: i64 }
recursive fn again(p: Packet, n: i64) -> Packet {
    if n == 0 { p.tag += 1; p.bytes[1199999] += 1; return p; }
    return again(p, n - 1);
}
fn stop() { return Packet { tag: 41, .. } from escaped; }
fn escaped() -> Packet { stop(); return Packet { tag: 0, .. }; }
fn main() {
    let original = Packet { tag: 7, .. };
    let result = again(original, 20);
    assert(result.tag == 8 && result.bytes[1199999] == 1);
    assert(original.tag == 7 && original.bytes[1199999] == 0);
    let jumped = escaped(); assert(jumped.tag == 41);
    for i in 0..100 { let scratch = again(original, 2); assert(scratch.tag == 8); }
    assert(original == Packet { tag: 7, .. });
    print("large values ok");
}
