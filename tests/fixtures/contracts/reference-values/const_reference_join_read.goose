fn first(r: const i64[3]&, rest: i64[>..]&, c: bool) -> i64 { let s = if c { r } else { rest[..] }; s[0] }
fn main() { var a: i64[3] = [1,2,3]; var b: i64[>..] = [4,5]; print(first(a,b,true)); }
