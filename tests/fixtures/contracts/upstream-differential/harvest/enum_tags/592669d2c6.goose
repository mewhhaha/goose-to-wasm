enum E { Empty, Data { tag:u8,word:u16 } }
var values:E[u8] = [E.Data{0x11,0x2233},E.Data{0x44,0x5566}];
export fn count()->i64 { values.len } fn main() {}