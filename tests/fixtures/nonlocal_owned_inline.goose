recursive fn leave(n:i64) { if n>0 {leave(n-1);return;} return [9] from effect; }
fn effect()->i64[>..] {leave(1);return [];}
inline fn choose(b:bool)->i64[>..]{var xs:i64[>..]=[1,2];if b{return[7];}return xs;}
export fn tick(n:i64)->i64{let xs=choose(n>0);return xs[0];}
fn main(){print(effect());print(tick(1));}
