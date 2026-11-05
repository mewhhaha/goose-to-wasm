fn main() {
    const k: i64 = 5; var other = 5;
    assert(k .== k && !(k .== other));
    print("const identity");
}
