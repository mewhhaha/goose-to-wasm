fn zap(p: u8[:]&) { for &e in p { e -= 32; } }
fn main() { var a: u8[3] = [97, 98, 99]; var s: u8[:] = a; zap(s); print(a); }
