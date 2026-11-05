struct H { s: u8[:] }
var g: u8[>..] = [];
fn mk() -> H { return H { s: g[0..2] }; }
fn load(p: u8[:]&) -> u8[:] { return p; }
fn main() { g.append("abc"); print(load(mk().s)); }
