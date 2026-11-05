enum Slot { Full { values: i64[3] }, Empty }
var calls = 0;
fn made(k: i64) -> Slot.. {
    calls++;
    return Slot.Full { [k, k * 2, k * 3] };
}
fn second(view: i64[:]) -> i64 {
    var scratch: i64[>..] = [100, 200, 300];scratch.push(400);
    return view[1] + scratch[0] * 0;
}
fn main() {
    let fallback = [0, 0, 0];
    assert(second(match made(10) { Full &part => part.values[..], Empty => fallback[..] }) == 20);
    assert(calls == 1);
    var local: Slot.. = Slot.Full { [7, 8, 9] };
    match local { Full &part => { part.values[1] = 41; }, Empty => {} }
    assert(second(match local { Full &part => part.values[..], Empty => fallback[..] }) == 41);
    print("receiving views ok");
}
