// Checking only, a program that declares no main anywhere is checked on its
// own, from its exports (upstream TypeCheck nomain).
export "check_roots_entry" fn entry() -> i32 { return helper(2) as i32; }
fn helper(x: i64) -> i64 { return x * 3; }
