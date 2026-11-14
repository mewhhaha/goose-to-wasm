recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
struct Packet { id:i64, values:i64[>..] }
fn observe()->i64 {
    print(41);
    return 42;
}
recursive fn initial()->Packet { return Packet { 41, [observe()] }; }
inline fn startup()->i64 {
    let packet=initial();
    print(packet.id," ",packet.values.len," ",packet.values[0]);
    let kept:const i64& =packet.id;
    packet.id+=3;
    print(kept," ",packet.id," ",packet.values[0]);
    return kept;
}
// O2 inlines this receiving constructor into _start. No ordinary function
// then registers a positive-prefix mapping before _start is emitted.
var initialized=startup();
fn main() {
    print(initialized);
    print(enable().len);
}
