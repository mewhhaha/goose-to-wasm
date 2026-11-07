struct Box { values: const i64[2] }
fn main() { var box = Box { values: [1, 2] }; let r = &box.values; r[0] = 9; }
