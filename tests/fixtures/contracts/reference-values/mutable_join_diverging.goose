fn touch(r: i64[3]&, rest: i64[>..]&, c: bool) { let s = if c { if c { r } else { return; } } else { rest[..] }; s[0] = 0; }
fn main() { var a: i64[3] = [1,2,3]; var b: i64[>..] = [4,5]; touch(a,b,true); print(a); }
