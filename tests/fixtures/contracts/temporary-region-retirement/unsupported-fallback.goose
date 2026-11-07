fn make() -> i64[][] { [[1, 2], [3]] }
fn main() { var total: i64 = 0; for row in make() { total += row.len; } print(total); }
