fn invoke<F>() { F(); }
fn target() -> i64 { invoke() { return 19; }; return 0; }
fn main() { print(target(), target()); }
