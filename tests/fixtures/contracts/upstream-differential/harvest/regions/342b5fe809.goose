var numbers: i64[2] = [10, 11];
fn sources(n: i64) -> i64[2], i64[:], i64 { return [n, n + 1], numbers[..], n + 2; }
fn roots(n: i64) -> i64[>..], i64[>..], i64 { return sources(n); }
export fn tick(n: i64) -> i64 {
    let a, b, c = roots(n);
    if a[1] != n + 1 || b[0] != 10 || c != n + 2 { abort("wrong adapted result"); } return a[1];
}
fn main() {}