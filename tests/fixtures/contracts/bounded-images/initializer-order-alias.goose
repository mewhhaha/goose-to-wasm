struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }]; var trace=0;
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn first() -> i64 { trace=trace*10+1; -65 }
fn second() -> Cell& { assert(trace==1); trace=trace*10+2; cells[0] }
fn third() -> u8 { assert(trace==12); trace=trace*10+3; cells[0].value=31; 5 }
fn main() { let v=Image { first(), second(), third() }; assert(trace==123 && v.prefix == -65 && v.link.value==31 && &v.link .== &cells[0] && v.tail==5); print("relative image initializer order and alias ok"); }
