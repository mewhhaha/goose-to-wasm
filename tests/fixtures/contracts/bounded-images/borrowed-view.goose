struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }];
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn value(p: Image&) -> i64 { p.link.value + p.tail }
fn forward(p: Image&) -> i64 { value(p) }
fn main() { let v=Image { 300, cells[0], 5 }; assert(forward(v)==22); print("borrowed relative image view ok"); }
