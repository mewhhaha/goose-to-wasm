extern fn bench_input() -> i64;
fn main() {
    var a = bench_input();
    var b = a;
    var pointer: i64&? = null;
    print(pointer == null);
    pointer .= &a;
    print(pointer != null);
    if pointer { print(pointer); }
    let ra = &a;
    let rb = &b;
    print(ra .== ra, " ", ra .== rb);
    var values: i64[3] = [1, 2, 3];
    var copied = copy(values);
    copied[0] = 9;
    print(values, " ", copied);
}
