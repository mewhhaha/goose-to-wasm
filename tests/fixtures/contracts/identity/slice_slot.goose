fn main() {
    var values: i64[2] = [1, 2]; var view: i64[:] = values[..];
    assert((&view) .== (&view));
    print("slice slot identity");
}
