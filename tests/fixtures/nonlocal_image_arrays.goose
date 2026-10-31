recursive fn leave_default(depth:i64) {
    if depth > 0 { leave_default(depth - 1); return; }
    return [7,8] from target_default;
}
recursive fn target_default() -> u16[] {
    var values: u16[>..] = [1,2]; leave_default(4); return values;
}
recursive fn leave_u8(depth:i64) {
    if depth > 0 { leave_u8(depth - 1); return; }
    return [7,8] from target_u8;
}
recursive fn target_u8() -> u16[u8] {
    var values: u16[>..] = [1,2]; leave_u8(4); return values;
}
recursive fn leave_u16(depth:i64) {
    if depth > 0 { leave_u16(depth - 1); return; }
    return [7,8] from target_u16;
}
recursive fn target_u16() -> u16[u16] {
    var values: u16[>..] = [1,2]; leave_u16(4); return values;
}
recursive fn leave_u32(depth:i64) {
    if depth > 0 { leave_u32(depth - 1); return; }
    return [7,8] from target_u32;
}
recursive fn target_u32() -> u16[u32] {
    var values: u16[>..] = [1,2]; leave_u32(4); return values;
}
recursive fn leave_u64(depth:i64) {
    if depth > 0 { leave_u64(depth - 1); return; }
    return [7,8] from target_u64;
}
recursive fn target_u64() -> u16[u64] {
    var values: u16[>..] = [1,2]; leave_u64(4); return values;
}
recursive fn leave_limited(depth:i64) {
    if depth > 0 { leave_limited(depth-1); return; }
    return [9,10] from target_limited;
}
recursive fn target_limited() -> u16[..] {
    var values:u16[..] = [..5]; values.push(1); leave_limited(4); return values;
}
fn main() {
    let value_default = target_default(); print(value_default.len," ",value_default[0] as i64," ",value_default[1] as i64);
    let value_u8 = target_u8(); print(value_u8.len," ",value_u8[0] as i64," ",value_u8[1] as i64);
    let value_u16 = target_u16(); print(value_u16.len," ",value_u16[0] as i64," ",value_u16[1] as i64);
    let value_u32 = target_u32(); print(value_u32.len," ",value_u32[0] as i64," ",value_u32[1] as i64);
    let value_u64 = target_u64(); print(value_u64.len," ",value_u64[0] as i64," ",value_u64[1] as i64);
    var value_limited = target_limited(); print(value_limited.cap," ",value_limited.len," ",value_limited[0] as i64," ",value_limited[1] as i64);
    print(value_limited.pop() as i64); value_limited.push(11); print(value_limited[1] as i64);
}
