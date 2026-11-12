// The reference checker's reachable-program build checks only the bodies
// that main or an export reaches, and the signatures of the rest.
struct Nodes { items: i64[:] = default<i64[:]>() }
fn unused(self_: const Nodes&, value: const i64&) -> i64 { return self_.items.index_of(value); }
fn main() { print(1); }
