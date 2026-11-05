fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
fn hop()->i64{return 18 from owner;}
fn owner()->i64{hop();0}
fn main(){print(owner());}
