struct Frame { depth: i64, marks: i64[>..] }
fn marks(f: Frame&) { return f.marks; }
fn main() { var f = Frame { depth: 1, marks: [1] }; print(marks(f)); }
