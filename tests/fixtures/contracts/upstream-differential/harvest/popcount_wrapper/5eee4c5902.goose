recursive fn wrapper8(value:u8)->u8 {
    var bits=value; var count:u8=0;
    while bits!=0 { bits&=bits-1; count++; }
    return count;
}
export fn apply8(value:u8)->u8 { return wrapper8(value); }
recursive fn wrapper16(value:u16)->i8 {
    var bits=value; var count:i8=0;
    while bits!=0 { bits&=bits-1; count++; }
    return count;
}
export fn apply16(value:u16)->i8 { return wrapper16(value); }
recursive fn wrapper32(value:u32)->u32 {
    var bits=value; var count:u32=0;
    while bits!=0 { bits&=bits-1; count++; }
    return count;
}
export fn apply32(value:u32)->u32 { return wrapper32(value); }
recursive fn wrapper64(value:u64)->i64 {
    var bits=value; var count:i64=0;
    while bits!=0 { bits&=bits-1; count++; }
    return count;
}
export fn apply64(value:u64)->i64 { return wrapper64(value); }
fn main() {}