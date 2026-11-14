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
var calls=0;
recursive fn input(value:i64)->u8 { calls++; return value as! u8; }
recursive fn seeded(value:u8)->i64 {
    var bits=value; var count=1;
    while bits!=0 { bits&=bits-1; count++; } return count;
}
recursive fn extra(value:u8)->i64 {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; calls++; } return count;
}
recursive fn changed(value:u8)->i64 {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; } return count+1;
}
recursive fn signed(value:i16)->i64 {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; } return count;
}
fn main() {
    print(wrapper8(input(256))," ",calls," ",wrapper8(input(-1))," ",calls);
    calls=0; print(seeded(255)," ",extra(255)," ",changed(255)," ",signed(127)," ",calls);
}