struct Box { s: u8[] }
fn show(s: const u8[]&) { print(s); }
fn main() { var b = Box { s: "abc" }; show(b.s); }
