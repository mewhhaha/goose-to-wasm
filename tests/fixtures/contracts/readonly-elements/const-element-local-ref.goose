struct Box { s: const u8[:] }
fn main() { var b = Box { s: "abc" }; let p = &b.s; for &e in p { e = 65; } }
