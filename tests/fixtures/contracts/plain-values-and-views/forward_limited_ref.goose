var table: u8[..5] = "ab";
fn refs() -> u8[..5]&, i64 { return table, 12; }
fn forward() -> u8[:], i64 { return refs(); }
fn main() { let view, n = forward(); print(view, " ", view.len, " ", table.cap, " ", n); }
