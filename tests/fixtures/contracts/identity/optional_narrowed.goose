fn main() {
    var a = 5; var p: i64? = a;
    assert(p .== a);
    if p { assert(a .== p); }
    p .= null;
    assert(p .== null && a .!= p);
    print("optional identity");
}
