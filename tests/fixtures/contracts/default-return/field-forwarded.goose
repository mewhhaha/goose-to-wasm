fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
struct S {a:i64=block {relay(){return 1;};0}}
fn main(){print(S{}.a);}
