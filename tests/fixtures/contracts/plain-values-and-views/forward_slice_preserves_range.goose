var table: u8[4] = "abcd";
fn refs() -> u8[:], i64 { return table[1..3], 14; }
fn forward() -> u8[:], i64 { return refs(); }
fn main() { let view, n = forward(); view[0] = 'z'; print(table, " ", view, " ", n); }
