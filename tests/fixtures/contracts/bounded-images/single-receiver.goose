struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 11 }, Cell { 22 }];
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u16 }
fn make(k: i64) -> Image { Image { k, cells[1], 54321 } }
fn forward(k: i64) -> Image { make(k) }
fn choose(first: bool) -> Image { if first { return forward(-65); } return make(64); }
fn main() { let a=choose(true); let b=choose(false); assert(a.prefix == -65 && a.link.value==22 && a.tail==54321 && b.prefix==64 && b.link.value==22); print("relative image single receiver ok"); }
