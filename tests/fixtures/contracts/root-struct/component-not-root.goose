// Upstream 32a4f44 test/errors_tc/root_component_not_root.goose:
// rejected: a named array component must be a direct field of a global root owner
struct State { items: i32[>..] }
var state = State { [] };
type Id = u32 in state.items;
fn main() {}
