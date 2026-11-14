extern fn root(x:f64)->f64="sqrt";
var values:i64[>..]=[9,16];
fn main() { print(root(values[0] as f64)," ",values.len); }