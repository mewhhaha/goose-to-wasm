struct H { s: u8[:] }
var g: u8[>..] = [];
fn mk() -> H { return H { s: g[0..2] }; }
fn adv(p: u8[:]&) { p = p[1..]; }
fn main() { g.append("abc"); var h = mk(); adv(h.s); print(h.s); }
