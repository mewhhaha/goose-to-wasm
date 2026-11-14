
fn invoke<F>(a:i32,b:i64)->bool { F(a,b) }
fn forward<F>(a:i32,b:i64)->bool { invoke(a,b) { x,y => F(x as i64,y) } }
fn run()->bool { forward(1,2) { x:i64,y:i64 => x<y } }
fn main() { print(run()); }
