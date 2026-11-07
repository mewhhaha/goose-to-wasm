struct Cell { value: i64 }
var cells: Cell[>..] = [];
struct Image { prefix: varint, link: Cell&<u8 in cells>, tail: u8 }
fn first() -> i64 { print("first initializer"); -65 }
fn last() -> u8 { print("UNREACHED later initializer"); 5 }
fn main() { for i in 40 { cells.push(Cell { i }); } let v=Image { first(), cells[35], last() }; print(v.tail); }
