struct Box { s: const u8[][:] }
fn zap(p: (const u8[][:])&) { for e in p { e[0] = 65; } }
fn main() { var a: u8[][>..] = []; a.push("abc"); var b = Box { s: a[..] }; zap(b.s); }
