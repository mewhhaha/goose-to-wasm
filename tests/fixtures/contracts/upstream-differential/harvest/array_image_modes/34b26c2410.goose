recursive fn produced()->i64[u8] { return [3,4]; }
fn main() { var grow:i64[>..]=produced(); grow.push(9); print(grow); }