fn inspect(values: i64[:]&, start: i64, tail: i64) {
    let invalid = values[start..^tail];
    print(invalid.len);
}
fn main() {
    var data: i64[6] = [10, 20, 30, 40, 50, 60];
    var view: i64[:] = data[1..];
    inspect(view, 4, 2);
}
