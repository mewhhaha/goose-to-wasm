extern fn gate() -> i64;
fn main() { var values: i64[>..] = [7, 9]; let view = values[0..2]; fn grow() { for i in 0..255 { values.push(i); } } grow(); print(view[0]); print(values.len); }
