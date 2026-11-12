// A whole-value read of an array assigned only element-wise is an error.
fn main() {
    var a: i64[3];
    a[0] = 1;
    let b = a;
    print(b[0]);
}
