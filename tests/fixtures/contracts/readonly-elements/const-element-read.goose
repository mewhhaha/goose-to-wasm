struct Box { s: const u8[:] }
fn read(p: (const u8[:])&) { for e in p { print(e); } }
fn main() { var b = Box { s: "ab" }; read(b.s); }
