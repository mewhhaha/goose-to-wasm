// Upstream 32a4f44 test/errors_tc/root_component_index_shrink.goose:
// rejected: an index type names state.items, so its length never goes down
root struct State { items: i32[>..] = [] }
var state = State {};
type Id = u32 in state.items;
fn reset(s: State&) { s.items.clear(); }
fn main() { state.items.push(1); reset(state); }
