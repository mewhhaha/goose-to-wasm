// Upstream 32a4f44 test/errors_tc/root_component_let_owner.goose:
// rejected: a relative reference's pool must be a var
root struct State { items: i32[>..] = [] }
let state = State {};
type Link = i32&<u32 in state.items>;
fn main() {}
