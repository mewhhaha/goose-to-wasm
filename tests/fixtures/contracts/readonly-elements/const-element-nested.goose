struct Box { s: const u8[:] }
struct H { b: Box }
fn zap(p: (const u8[:])&) { for &e in p { e = 65; } }
fn main() { var h = H { b: Box { s: "abc" } }; zap(h.b.s); }
