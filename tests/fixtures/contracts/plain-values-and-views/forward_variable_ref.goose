var table: u8[] = "abc";
fn refs() -> u8[]&, i64 { return table, 15; }
fn forward() -> u8[:], i64 { return refs(); }
fn main() { let view, n = forward(); print(view, " ", view.len, " ", n); }
