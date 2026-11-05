fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
fn helper()->i64{relay(){return 7;};0}
fn first(a:i64=helper())->i64{a}
fn main(){print(first());}
