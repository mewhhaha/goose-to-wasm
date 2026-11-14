
fn invoke<F>(a:i64&,b:i64&)->bool { F(a,b) }
fn forward<F>(a:i64&,b:i64&)->bool { invoke(a,b) { x,y => F(x,y) } }
fn run()->bool { var a=1; var b=2; forward(a,b) { x,y => x<y } }
fn main() { print(run()); }
