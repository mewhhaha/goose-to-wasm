fn stop()->i64{return 9 from c;} fn c()->i64{return[11,stop()] from a;}
fn a(flag:bool)->i64[>..]{var xs:i64[>..]=[1,2];if flag{print(c());}return xs;}
fn main(){var xs=a(true);print(xs);xs.push(7);print(xs," ",xs.pop());}
