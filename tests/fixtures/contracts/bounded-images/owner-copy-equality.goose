struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }];
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn copied(p: Image&) -> Image { copy(p) }
fn main() { var a=Image { -65, cells[0], 5 }; var b=copied(a); assert(a==b); b.tail=9; assert(a.tail==5 && b.tail==9 && a!=b); print("bounded image copy equality ok"); }
