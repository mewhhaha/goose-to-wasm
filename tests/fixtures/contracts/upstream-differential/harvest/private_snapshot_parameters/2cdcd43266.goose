recursive fn length(xs:i64[>..])->i64 { xs.len }
fn main() { var xs:i64[>..]=[1,2]; print(length(copy(xs))); }
