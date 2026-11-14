struct Packet { tag: u8, id: i64, values: i64[] }
recursive fn make(n: i64) -> Packet { var packet = Packet { 1, n, [n, n + 1] }; return packet; }
recursive fn changed(packet: Packet) -> Packet { packet.id += 10; packet.values[0] += 20; return packet; }
export fn tick(n: i64) -> i64 {
    let a = make(n); let b = copy(a); let c = changed(copy(a));
    let kept: const i64& = a.id; b.values[0] += 100;
    if kept != n || a.values[0] != n || b.values[0] != n + 100 || c.id != n + 10 || c.values[0] != n + 20 { abort("bad struct copy"); }
    for i in 100 { if make(i).id != i { abort("bad struct temporary"); } }
    if kept != n || a.values[0] != n { abort("overwritten struct"); }
    return n + 1;
}
fn main() {}