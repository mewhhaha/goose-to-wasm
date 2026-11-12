// Nor as a slice element.
root struct State { count: i64 }
struct Wrapper { states: State[:] }
fn main() {}
