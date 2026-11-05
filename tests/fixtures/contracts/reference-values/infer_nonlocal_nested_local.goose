struct Frame { depth: i64, marks: i64[>..] }
fn marks() { fn leave() { var f = Frame { depth: 1, marks: [1] }; return f from marks; } leave(); }
fn main() { print(marks()); }
