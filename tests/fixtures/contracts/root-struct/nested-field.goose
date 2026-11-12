// A root owner is owned only by a local or global variable.
root struct State { count: i64 }
struct Wrapper { state: State }
fn main() {}
