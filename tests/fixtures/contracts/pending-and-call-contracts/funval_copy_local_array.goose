fn each<F>() { var a: i64[>..] = [1, 2]; F(if true { a } else { a }); }
fn main() { each() { v => print(v.len) }; }
