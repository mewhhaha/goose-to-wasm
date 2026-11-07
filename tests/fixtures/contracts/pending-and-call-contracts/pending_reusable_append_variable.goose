struct V { text: u8[] }
fn main() { var values: V[] = [V { "abc" }]; reusable var pool = []; pool.append(values); }
