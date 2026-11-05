fn format(out: u8[>..]&, value: const i64[:]) { value[0] = 9; }
fn main() { var values: i64[>..] = [1]; let readonly: const i64[:] = values[..]; print(readonly); }
