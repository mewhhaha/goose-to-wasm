recursive fn make(n: i64) -> i64[>..] {
    if n <= 0 { return [1]; }
    return make(n - 1);
}
fn main() { let values = make(3); print(values.len); }
