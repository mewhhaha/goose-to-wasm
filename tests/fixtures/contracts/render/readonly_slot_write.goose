fn format(out: u8[>..]&, value: i64[:]&) { value = value[1..]; }
fn main() { var values: i64[>..] = [1, 2, 3]; print(values[1..]); }
