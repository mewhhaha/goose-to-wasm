extern fn gate() -> i64;
var values: i64[>..] = [7, 9];
fn grow() -> i64 { for i in 0..255 { values.push(i); } return values.len; }
fn use(value: i64 = grow()) { print(value); }
fn main() { use(); print(values[0]); }
