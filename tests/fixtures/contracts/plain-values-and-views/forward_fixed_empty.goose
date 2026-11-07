var table: u8[0] = [];
fn refs() -> u8[0]&, i64 { return table, 11; }
fn forward() -> u8[:], i64 { return refs(); }
fn main() { let view, n = forward(); print(view.len, " ", n); }
