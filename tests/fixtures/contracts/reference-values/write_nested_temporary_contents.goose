struct H { s: u8[:] }
struct W { h: H }
var g: u8[>..] = [];
fn mk() -> W { W { h: H { s: g[0..2] } } }
fn main() { g.append("abc"); mk().h.s[0] = 'z'; print(g); }
