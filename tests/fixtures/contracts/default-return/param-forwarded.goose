fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
fn first(a:i64=block { relay() { return 1; };0})->i64{a}
fn main(){print(first());}
