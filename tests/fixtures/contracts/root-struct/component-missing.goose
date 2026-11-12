// Upstream 32a4f44 test/errors_tc/root_component_missing.goose:
// rejected: root struct State has no field missing
root struct State { items: i32[>..] = [] }
var state = State {};
type Id = u32 in state.missing;
fn main() {}
