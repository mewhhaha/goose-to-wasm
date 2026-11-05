fn zap(p: u8[][:]&) { for e in p { e[0] -= 32; } }
fn main() { var a: u8[][>..] = []; a.push("abc"); var s: u8[][:] = a[..]; zap(s); for e in a { print(e); } }
