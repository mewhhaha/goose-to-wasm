struct Cell { value:i64 }
var cells:Cell[>..]=[];
struct Image { pad 0, prefix:varint, pad 0, link:Cell&<varint in cells>, pad 0, pad 2, pad 0, tail:u8, pad 0 }
fn read(v:Image&)->i64 { v.link.value + v.tail as i64 }
fn main(){ cells.push(Cell{117}); cells.push(Cell{122}); var v=Image{-65,cells[0],91}; let duplicate=copy(v); print(v); print(v==duplicate); v.tail = 96; print(v==duplicate); print(read(v)); }
