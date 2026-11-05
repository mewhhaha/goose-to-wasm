fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
fn first(a:i64=block{fn local()->i64{relay(){return 9;};0} local()})->i64{a}
fn main(){print(first());}
