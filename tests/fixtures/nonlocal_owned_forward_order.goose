fn invoke<F>(b:bool){if b{F();}} fn seven(x:i64)->i64[>..]{return[7];}
fn target(b:bool)->i64[>..]{var xs:i64[>..]=[1,2];invoke(b){return seven(xs.push(3));}return xs;}
fn main(){var xs=target(true);print(xs);xs.push(8);print(xs," ",xs.pop());}
