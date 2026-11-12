// Passing the array reads it.
fn first(x: i64[3]) -> i64 { x[0] }
fn main() {
    var a: i64[3];
    a[0] = 1;
    print(first(a));
}
