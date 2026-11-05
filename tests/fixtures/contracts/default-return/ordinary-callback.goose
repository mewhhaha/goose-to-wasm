fn call<F>() { F(); }
fn relay<G>() { call() { G(); }; }
fn owner()->i64{relay(){return 17;};0}
fn main(){print(owner());}
