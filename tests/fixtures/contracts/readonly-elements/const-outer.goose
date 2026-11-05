fn zap(p: const (u8[:])&) { for &e in p { e = 65; } }
fn main() { var a: u8[3] = [97, 98, 99]; var s: u8[:] = a; zap(s); }
