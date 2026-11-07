fn invoke<F>() { F(); }
fn target() -> i64 { invoke() { return 17 from target; }; return 0; }
fn main() { print(target(), target()); }
