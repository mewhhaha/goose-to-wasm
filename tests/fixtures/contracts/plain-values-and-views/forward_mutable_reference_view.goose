var table: u8[3] = [97, 98, 99];
fn refs() -> u8[3]&, i64 { return table, 7; }
fn forward() -> u8[:], i64 { return refs(); }
fn main() { let view, n = forward(); view[0] = 'z'; print(table, " ", view, " ", n); }
