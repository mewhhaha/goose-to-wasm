struct Frame { depth: i64, marks: i64[>..] }
fn marks() { var f = Frame { depth: 1, marks: [1] }; return copy(f.marks); }
fn main() { print(marks()); }
