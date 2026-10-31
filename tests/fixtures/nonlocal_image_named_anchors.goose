recursive fn stop_var() -> u8 { return 9 from cancel_var; }
recursive fn cancel_var() -> i64 { return [stop_var();3] from target_var; }
recursive fn target_var() -> u8[u8] { print(cancel_var()); var values:u8[u8] = [7]; return values; }
recursive fn stop_grow() -> u8 { return 9 from cancel_grow; }
recursive fn cancel_grow() -> i64 { return [stop_grow();3] from target_grow; }
recursive fn target_grow() -> u8[u8] { print(cancel_grow()); var values:u8[>..] = [7]; return values; }
recursive fn stop_limited() -> u8 { return 9 from cancel_limited; }
recursive fn cancel_limited() -> i64 { return [stop_limited();3] from target_limited; }
recursive fn target_limited() -> u8[..] { print(cancel_limited()); var values:u8[..] = [..4]; values.push(7); return values; }
recursive fn stop_empty() -> u8 { return 9 from cancel_empty; }
recursive fn cancel_empty() -> i64 { return [stop_empty();3] from target_empty; }
recursive fn target_empty() -> u8[u8] { print(cancel_empty()); return []; }
fn main() {
    let value_var=target_var(); print(value_var.len);
    let value_grow=target_grow(); print(value_grow.len);
    let value_limited=target_limited(); print(value_limited.cap," ",value_limited.len);
    let value_empty=target_empty(); print(value_empty.len);
}
