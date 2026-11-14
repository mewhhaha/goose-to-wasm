export fn blow(index:i64)->u8 {
    var bytes:u8[60000]=[index as! u8;60000];
    assert(index!=0); return bytes[1];
}
recursive fn allocate(index:i64)->u8 {
    var bytes:u8[60000]=[index as! u8;60000];
    bytes[0]=bytes[59999]+1; return bytes[1];
}
export fn next(index:i64)->u8 { return allocate(index); }
fn main() { print(1); print(next(7)); }
