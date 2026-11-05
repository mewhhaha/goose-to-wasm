struct Box { s: const u8[:] }
fn skip(p: (const u8[:])&) { p = p[1..]; }
fn main() { var b = Box { s: "abc" }; skip(&b.s); let p = &b.s; p = p[1..]; print(b.s); }
