var values:i64[u64]=[7,8];
fn main() { var grow:i64[>..]=copy(values); grow.push(9); print(grow," ",values.len); }