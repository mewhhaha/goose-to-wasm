struct Cell { value: i64 }
var cells: Cell[>..] = [];
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
struct Optional { prefix: varint, link: Cell&<varint in cells>?, tail: u8 }
fn main() { for i in 40 { cells.push(Cell { 100+i }); } let v=Image { -65, cells[17], 91 }; assert(v.prefix == -65 && v.link.value == 117 && v.tail == 91); let loaded=&v.link; assert(loaded .== &cells[17]); let nil=Optional { 64, null, 72 }; assert(nil.link==null && nil.tail==72); print("varint cell in variable image ok"); }
