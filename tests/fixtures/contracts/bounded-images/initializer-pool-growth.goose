struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }]; var trace=0;
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn selected() -> Cell& { trace=1; cells[0] }
fn grown() -> u8 { assert(trace==1); for i in 65536 { cells.push(Cell { 100+i }); } cells[0].value=31; trace=2; 5 }
fn main() { let v=Image { -65, selected(), grown() }; assert(trace==2 && cells.len==65537 && v.link.value==31 && &v.link .== &cells[0] && v.tail==5); print("relative image leaf survives pool growth"); }
