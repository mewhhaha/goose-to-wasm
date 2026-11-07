var table: u8[>..] = "ab";
fn refs() -> u8[>..]&, i64 { return table, 13; }
fn forward() -> u8[:], i64 { return refs(); }
fn main() { table.push('c'); let view, n = forward(); print(view, " ", view.len, " ", n); }
