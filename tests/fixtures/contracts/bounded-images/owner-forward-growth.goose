struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }];
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn read(p: Image&) -> i64 { p.link.value }
fn forward(p: Image&) -> i64 { let alias .= p; let first=read(alias); for i in 65536 { cells.push(Cell { i }); } cells[0].value=31; assert(alias .== p); first+read(p)+read(alias) }
fn main() { let v=Image { -65, cells[0], 5 }; assert(forward(v)==79 && read(v)==31); print("image owner forwarding survives pool growth"); }
