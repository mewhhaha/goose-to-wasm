fn main() {
    var a = 5; var b = 5;
    assert(a .== a && !(a .== b) && a .!= b);
    print("scalar identity");
}
