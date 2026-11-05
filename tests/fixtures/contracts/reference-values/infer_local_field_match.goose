struct Frame { depth: i64, marks: i64[>..] }
fn marks(c: i64) { var f = Frame { depth: 1, marks: [1] }; match c { 0 => f.marks, _ => f.marks } }
fn main() { print(marks(0)); }
