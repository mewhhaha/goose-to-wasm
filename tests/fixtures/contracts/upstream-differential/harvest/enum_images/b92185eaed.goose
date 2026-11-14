enum E {Empty,Data{tag:u8,word:u16},Big{values:u64[8192]}} var e:E..=E.Data{0x11,0x2233};
fn main() {}