// An unknown type behind a reference parameter is diagnosed where it is
// named; checking the uses of that parameter and the call that passes one
// on reports errors rather than failing inside the checker.
fn walk(n: Node&) { let l = n.left; walk(l); }
fn main() {}
