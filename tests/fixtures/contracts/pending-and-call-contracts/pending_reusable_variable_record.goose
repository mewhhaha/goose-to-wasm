struct Variable { bytes: u8[] }
fn main() { reusable var pool = []; pool.push(Variable { bytes: "abc" }); }
