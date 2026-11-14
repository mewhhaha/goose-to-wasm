struct Cell{tag:u8,value:u16}
var rows:Cell[..256][>..]=[[Cell{0x11,0x2233},Cell{0x44,0x5566}]];
export fn count()->i64{rows[0].len} fn main(){}