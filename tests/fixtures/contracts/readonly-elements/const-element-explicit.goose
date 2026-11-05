struct Box { s: const u8[:] }
fn zap(p: (const u8[:])&) { for &e in p { e = 65; } }
fn main() { var b = Box { s: "abc" }; zap(&b.s); }
