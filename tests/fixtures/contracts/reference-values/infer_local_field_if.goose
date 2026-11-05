struct Frame { depth: i64, marks: i64[>..] }
fn marks(c: bool) { var f = Frame { depth: 1, marks: [1] }; if c { f.marks } else { f.marks } }
fn main() { print(marks(true)); }
