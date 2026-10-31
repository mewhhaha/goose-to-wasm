recursive fn leave(n:i64) { if n>0 {leave(n-1);return;} return [9] from effect; }
fn effect()->i64[>..] {leave(1);return [];}
recursive fn choose(b:bool)->i64[>..]{var xs:i64[>..]=[1,2];if b{return[7];}return xs;}
fn main(){print(effect());var xs=choose(true);print(xs);xs.push(8);print(xs);}
