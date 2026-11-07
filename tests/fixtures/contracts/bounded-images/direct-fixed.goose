struct Cell { value: i64 }
var cells: Cell[>..] = [];
struct Image { prefix: varint, link: Cell&<u16 in cells>, pad 2, tail: u32 }
fn main() { for i in 40 { cells.push(Cell { 100+i }); } var v=Image { -65, cells[17], 0x12345678 }; assert(v.prefix == -65 && v.link.value == 117 && v.tail == 0x12345678); v.link .= cells[2]; assert(v.link.value == 102 && v.tail == 0x12345678); print("fixed cell in variable image ok"); }
