recursive fn enable(n:i64){if n>0{enable(n-1);return;}return [99] from enabled;}
fn enabled()->i64[>..]{enable(1);return [];}
inline fn choose(b:bool)->i64[>..]{var xs:i64[>..]=[1,2];if b{return [7];}return xs;}
fn outer(b:bool)->i64[>..]{return choose(b);}
export fn tick(n:i64)->i64{var xs=outer(n>0);return xs[0];}
fn main(){print(enabled());print(tick(1));}
