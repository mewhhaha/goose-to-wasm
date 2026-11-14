var values: u16[..] = [..5];
export fn count() -> i64 { values.cap * 100 + values.len }
fn main() { values.push(0x1122); values.push(0x3344); }