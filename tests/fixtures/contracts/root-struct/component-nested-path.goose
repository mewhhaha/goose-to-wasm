// Upstream 32a4f44 test/errors_tc/root_component_nested_path.goose:
// rejected: a named array component must be a direct field of a global root owner
struct Tail { items: i32[>..] }
root struct State { tail: Tail }
var state = State { Tail { [] } };
type Link = i32&<u32 in state.tail.items>;
fn main() {}
