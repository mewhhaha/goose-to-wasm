fn make(n: i64) -> i64[>..], i64[>..] {
    var a: i64[>..] = [n]; var b: i64[>..] = [n + 1]; return a, b;
}
export fn tick(n: i64) -> i64 {
    let a, b = make(n); a[0] += 100;
    if b[0] != n + 1 { abort("aliased result regions"); } return b[0];
}
fn main() {}