struct Frame { depth: i64, marks: i64[>..] }
fn marks() { var f = Frame { depth: 1, marks: [1] }; return f; }
fn main() { var f = marks(); print(f.marks); }
