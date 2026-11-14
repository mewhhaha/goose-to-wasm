struct Packet { id: i64, values: i64[>..] }
enum Event { Data { id: i64, values: i64[] } }
export fn tick(n: i64) -> i64 {
    var packet = Packet { n, [n] }; let e: Event.. = Event.Data { n, [n] };
    recursive fn change() -> i64, i64 {
        packet.id += 1; packet.values.push(packet.id);
        let value = match e { Data &p => { p.id += 2; p.values[0] += 10; p.id + p.values[0] } };
        return packet.values[1], value;
    }
    let a, b = change();
    if a != n + 1 || b != 2 * n + 12 || packet.id != n + 1 { abort("bad captured owners"); } return n + 1;
}
fn main() {}