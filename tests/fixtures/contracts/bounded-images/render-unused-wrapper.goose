struct Cell { value:i64 }
var cells:Cell[>..]=[Cell{17}];
struct Image { prefix:varint, link:Cell&<varint in cells>, tail:u8 }
struct Wrap { view:Image& }
fn main(){let v=Image{1,cells[0],7};let w=Wrap{v};print(1);}
