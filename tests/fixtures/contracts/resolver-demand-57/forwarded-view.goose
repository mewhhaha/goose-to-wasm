extern fn gate() -> i64;
fn main() { var values: i64[>..] = [7, 9]; let view = values[0..2]; for i in 0..255 { values.push(i); } print(view[0]); print(view[1]); print(values.len); }
