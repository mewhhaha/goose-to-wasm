fn main() { var payload: u8[3] = [1, 2, 3]; var total: i64 = 0; for i in 0..10000 { total += to_bytes(payload).len; } print(total); }
