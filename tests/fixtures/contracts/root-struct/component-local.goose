// Upstream 32a4f44 test/errors_tc/root_component_local.goose:
// rejected: a relative reference's pool must be a global variable
root struct State { items: i32[>..] = [] }
type Link = i32&<u32 in state.items>;
fn main() { var state = State {}; }
