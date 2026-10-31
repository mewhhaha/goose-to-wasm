extern fn bench_input() -> i64;
struct Cell<T> { tag: u8, value: T }
enum E { Old { items: Cell<u16>[2] }, New { word: u32, tail: u16 } }
var fallback16: u16 = 0; var fallback32: u32 = 0;
recursive fn forward(named: bool) -> E.., u16, u16 {
    var e: E.. = E.Old { [Cell<u16> { 0, 0 }, Cell<u16> { 0, 0 }] };
    let x: u16& = match e { Old &p => p.items[0].value, _ => fallback16 };
    let y: u16& = match e { Old &p => p.items[1].value, _ => fallback16 };
    if named { return e, 0, 0; } return E.New { 0x01020304, 0x0506 }, x, y;
}
recursive fn reverse(named: bool) -> E.., u32, u16 {
    var e: E.. = E.New { 0, 0 };
    let x: u32& = match e { New &p => p.word, _ => fallback32 };
    let y: u16& = match e { New &p => p.tail, _ => fallback16 };
    if named { return e, 0, 0; }
    return E.Old { [Cell<u16> { 0xaa, 0x1122 }, Cell<u16> { 0xbb, 0x3344 }] }, x, y;
}
fn main() { let named = bench_input() > 0; let a,x,y=forward(named); let b,z,w=reverse(named); print(x," ",y," ",z," ",w); }
