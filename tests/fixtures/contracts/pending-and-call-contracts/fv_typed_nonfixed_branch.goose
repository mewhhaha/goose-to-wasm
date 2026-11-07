fn invoke<F>(x: i64[>..]&, y: i64[>..]&) { F(if true { x } else { y }); }
fn main() { var x: i64[>..] = [1, 2]; var y: i64[>..] = [4]; invoke(x, y) { v: i64[>..]& => v.push(3); }; print(x.len, " ", y.len); }
