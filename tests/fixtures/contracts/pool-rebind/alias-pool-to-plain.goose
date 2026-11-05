reusable var a: i64[>..] = [1]; var plain: i64[>..] = [2];
fn main() { let q: i64[>..]& = a; var p: i64[>..]& = q; p .= plain; }
