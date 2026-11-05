fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
struct S{a:i64=block{fn local()->i64{relay(){return 10;};0} local()}}
fn main(){print(S{}.a);}
