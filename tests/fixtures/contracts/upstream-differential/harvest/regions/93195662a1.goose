var first: i64[>..] = [987654321];
var second: i64[>..] = [22];
fn helper() -> i64 { var local: i64[>..] = [3]; return local[0]; }
fn main() { var caller: i64[>..] = [4]; print(helper() + caller[0]); }