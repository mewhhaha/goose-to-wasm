// Upstream 32a4f44 test/errors_tc/root_component_nonarray.goose:
// rejected: a relative reference's pool must be a grow-only resizable global
root struct State { count: i32 = 0 }
var state = State {};
type Link = i32&<u32 in state.count>;
fn main() {}
