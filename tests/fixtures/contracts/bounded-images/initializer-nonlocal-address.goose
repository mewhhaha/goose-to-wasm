struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }]; var trace=0;
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn first() -> i64 { trace=trace*10+1; -65 }
fn last() -> u8 { trace=trace*10+2; 5 }
fn make<F>() -> Image { Image { first(), F(), last() } }
fn trial(cancel: bool) -> i64 {
    trace=0;
    let v=make() { if cancel { return 77 from trial; } &cells[0] };
    assert(v.prefix == -65 && v.tail==5);
    v.link.value
}
fn main() { assert(trial(true)==77 && trace==1); assert(trial(false)==17 && trace==12); print("relative image initializer exit ok"); }
