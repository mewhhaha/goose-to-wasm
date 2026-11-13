// Unequal lengths abort before any element is written.
fn main() {
    var a = [1, 2, 3];
    a[1..].move_from(a[..1]);
    print(a[0]);
}
