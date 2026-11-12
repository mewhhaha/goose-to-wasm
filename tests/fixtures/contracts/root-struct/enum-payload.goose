// Nor as an enum payload field.
root struct State { count: i64 }
enum Choice { Empty, Owned { state: State } }
fn main() {}
