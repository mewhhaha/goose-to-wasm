inline fn produced()->i64[varint] { return [3,4]; }
fn main() { var grow:i64[>..]=produced(); grow.push(9); print(grow); }