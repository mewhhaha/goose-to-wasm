fn invoke<F>(x: i64[>..]&) { F(x); }
fn main() { var x: i64[>..] = [1, 2]; invoke(x) { v => v.push(3); print(v.len); }; print(x.len); }
