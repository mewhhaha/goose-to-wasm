recursive fn stop_u8() -> u8 { return 9 from cancel_u8; }
recursive fn cancel_u8() -> i64 { return [11,stop_u8()] from target_u8; }
recursive fn target_u8() -> u8[u8] { print(cancel_u8()); return [7]; }
recursive fn stop_u16() -> u8 { return 9 from cancel_u16; }
recursive fn cancel_u16() -> i64 { return [11,stop_u16()] from target_u16; }
recursive fn target_u16() -> u8[u16] { print(cancel_u16()); return [7]; }
recursive fn stop_limited() -> u8 { return 9 from cancel_limited; }
recursive fn cancel_limited() -> i64 { return [11,stop_limited()] from target_limited; }
recursive fn target_limited() -> u8[..] { print(cancel_limited()); return [7]; }
fn main() {
    let value_u8 = target_u8(); print(value_u8.len," ",value_u8[0] as i64," ",value_u8[1] as i64);
    let value_u16 = target_u16(); print(value_u16.len," ",value_u16[0] as i64," ",value_u16[1] as i64);
    let value_limited=target_limited(); print(value_limited.cap," ",value_limited.len," ",value_limited[0] as i64," ",value_limited[1] as i64);
}
