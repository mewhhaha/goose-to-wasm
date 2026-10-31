fn fixed() -> i64[2], i64 { return [1, 2], 3; }
fn promoted() -> i64[>..], i64 { return fixed(); }
fn main() { let values, n = promoted(); print(values, " ", n); }
