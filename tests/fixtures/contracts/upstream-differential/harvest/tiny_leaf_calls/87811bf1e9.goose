fn exchange_i8(xs:i8[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_u8(xs:u8[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_i16(xs:i16[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_u16(xs:u16[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_i32(xs:i32[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_u32(xs:u32[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_i64(xs:i64[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_u64(xs:u64[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_f32(xs:f32[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_f64(xs:f64[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn exchange_bool(xs:bool[:]) { let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }
fn narrow(xs:u8[:],value:u8) { xs[0]=((xs[0] as u64)+(value as u64)) as! u8; }
recursive fn drive() { var v_i8:i8[2]=[3,7]; var v_u8:u8[2]=[3,7]; var v_i16:i16[2]=[3,7]; var v_u16:u16[2]=[3,7]; var v_i32:i32[2]=[3,7]; var v_u32:u32[2]=[3,7]; var v_i64:i64[2]=[3,7]; var v_u64:u64[2]=[3,7]; var v_f32:f32[2]=[1.25,2.5]; var v_f64:f64[2]=[1.25,2.5]; var v_bool:bool[2]=[false,true]; var narrowed:u8[1]=[250]; exchange_i8(v_i8[..]); exchange_u8(v_u8[..]); exchange_i16(v_i16[..]); exchange_u16(v_u16[..]); exchange_i32(v_i32[..]); exchange_u32(v_u32[..]); exchange_i64(v_i64[..]); exchange_u64(v_u64[..]); exchange_f32(v_f32[..]); exchange_f64(v_f64[..]); exchange_bool(v_bool[..]); narrow(narrowed[..],10); print(v_i8[0]," ",v_i8[1]); print(v_u8[0]," ",v_u8[1]); print(v_i16[0]," ",v_i16[1]); print(v_u16[0]," ",v_u16[1]); print(v_i32[0]," ",v_i32[1]); print(v_u32[0]," ",v_u32[1]); print(v_i64[0]," ",v_i64[1]); print(v_u64[0]," ",v_u64[1]); print(v_f32[0]," ",v_f32[1]); print(v_f64[0]," ",v_f64[1]); print(v_bool[0]," ",v_bool[1]); print(narrowed[0]); }
fn main() { drive(); }
