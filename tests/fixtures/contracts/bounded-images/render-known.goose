struct Cell { value:i64 }
var cells:Cell[>..]=[Cell{17}];
struct Image { prefix:varint, link:Cell&<varint in cells>, tail:u8 }
fn show(p:Image&){ print(p); print(str(p)); var text:u8[>..]=[]; text.format(p); print(text); }
fn main(){let v=Image{1,cells[0],7};show(v);}
