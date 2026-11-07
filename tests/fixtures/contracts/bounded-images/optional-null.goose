struct Cell { value:i64 }
var cells:Cell[>..]=[Cell{17}];
struct Image { prefix:varint, link:Cell&<varint in cells>, tail:u8 }
fn optional(p:Image&?)->bool { p==null }
fn main(){ print(optional(null)); }
