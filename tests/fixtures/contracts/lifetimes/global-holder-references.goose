// A global holder may reference a whole grow-shrink global whose elements
// hold slices: the holder's own slots reach the array, not its elements.
struct Function { start: u32, borrowed: const u32[:] = default<const u32[:]>() }
struct Module { functions: Function[>..<]&, count: i64 = 0 }
var backing_functions: Function[>..<] = [];
var backing_module: Module = Module { functions: backing_functions, .. };
fn main() { backing_module.functions.push(Function { start: 1 }); print(backing_module.functions.len); }
