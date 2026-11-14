var rows:u8[>..]=[17,34,51];
export fn count()->i64 { rows.len }
export fn first()->u8 { rows[0] }
export fn clear() { rows.clear(); }
export fn resize() { rows.resize(6,0); }
fn main() {}
