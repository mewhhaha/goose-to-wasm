fn stop()->i64{return 9 from c;}
fn c()->i64{return [11,stop()] from a;}
fn a(flag:bool)->i64[>..]{if flag{print(c());}let ys=[7];return copy(ys);}
fn main(){var xs=a(true);print(xs);xs.push(8);print(xs);}
