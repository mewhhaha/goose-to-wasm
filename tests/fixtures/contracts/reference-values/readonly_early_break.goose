fn go(r: const i64[3]&, m: i64[3]&, rest: i64[>..]&, c: bool, d: bool) { let s=if c { block { if d { break r; } m } } else { rest[..] }; s[0]=0; }
fn main() { var a:i64[3]=[1,2,3]; var b:i64[3]=[4,5,6]; var more:i64[>..]=[7];go(a,b,more,true,true);print(a,b); }
