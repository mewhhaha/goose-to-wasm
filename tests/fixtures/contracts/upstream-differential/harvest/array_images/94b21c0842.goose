struct Cell { tag:u8, value:u16 }
var values: Cell[u8] = [Cell {1,0x1122},Cell {2,0x3344}];
export fn count() -> i64 { values.len } fn main() {}