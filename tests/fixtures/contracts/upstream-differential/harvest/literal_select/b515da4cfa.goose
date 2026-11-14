export fn pick_i8(flag:bool)->i8 { if flag { 12 } else { 34 } }
export fn pick_u8(flag:bool)->u8 { if flag { 0 } else { 255 } }
export fn pick_i16(flag:bool)->i16 { if flag { 123 } else { 32767 } }
export fn pick_u16(flag:bool)->u16 { if flag { 0 } else { 65535 } }
export fn pick_i32(flag:bool)->i32 { if flag { 17 } else { 2147483647 } }
export fn pick_u32(flag:bool)->u32 { if flag { 0 } else { 4294967295 } }
export fn pick_i64(flag:bool)->i64 { if flag { 37 } else { 9223372036854775807 } }
export fn pick_u64(flag:bool)->u64 { if flag { 0 } else { 18446744073709551615 } }
fn main(){print(pick_i8(true)," ",pick_i8(false));print(pick_u8(true)," ",pick_u8(false));print(pick_i16(true)," ",pick_i16(false));print(pick_u16(true)," ",pick_u16(false));print(pick_i32(true)," ",pick_i32(false));print(pick_u32(true)," ",pick_u32(false));print(pick_i64(true)," ",pick_i64(false));print(pick_u64(true)," ",pick_u64(false));}