fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
fn helper()->i64{relay(){return 8;};0}
struct S{a:i64=helper()}
fn main(){print(S{}.a);}
