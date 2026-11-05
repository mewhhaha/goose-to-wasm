fn zap(p: const (const u8[:])&) { for &e in p { e = 65; } }
fn main() { var s: const u8[:] = "abc"; zap(s); }
