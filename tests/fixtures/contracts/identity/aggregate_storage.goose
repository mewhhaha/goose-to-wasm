struct Pair { x: i64 }
fn main() {
    var a = Pair { x: 5 }; var b = Pair { x: 5 };
    var xs: i64[2] = [1, 2]; var ys: i64[2] = [1, 2];
    assert(a .== a && !(a .== b));
    assert(xs .== xs && xs .!= ys);
    print("aggregate identity");
}
