var table: u8[3] = "abc";
fn forward(r: u8[3]&?) -> u8[:], i64 { if r { return r, 16; } return table[0..0], 0; }
fn main() { let view, n = forward(table); print(view, " ", view.len, " ", n); }
