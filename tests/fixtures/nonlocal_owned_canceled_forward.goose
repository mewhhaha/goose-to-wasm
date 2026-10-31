fn stop()->i64{return 9 from c;}
fn c()->i64{return [11,stop()] from a;}
recursive fn seven(n:i64)->i64[>..]{if n>0{return seven(n-1);}return [7];}
fn a(flag:bool)->i64[>..]{if flag{print(c());}return seven(0);}
fn main(){var xs=a(true);print(xs);xs.push(8);print(xs);}
