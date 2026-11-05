struct H { s: u8[:] }
var g: u8[>..] = [];
fn mk() -> H { return H { s: g[0..2] }; }
fn main() { g.append("abc"); mk().s[0] = 'z'; print(g); }
