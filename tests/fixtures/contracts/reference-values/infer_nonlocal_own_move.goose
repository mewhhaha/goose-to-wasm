struct Frame { depth: i64, marks: i64[>..] }
fn marks() { var f = Frame { depth: 1, marks: [1] }; fn leave() { return f from marks; } leave(); f }
fn main() { var f = marks(); print(f.marks); }
