fn main() {
    var a = 5;
    assert(!(a .== null) && !(null .== a));
    assert(null .!= a && a .!= null);
    print("null identity");
}
