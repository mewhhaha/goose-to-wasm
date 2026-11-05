var values: i64[2] = [5, 5];
var calls = 0;
fn next() -> i64 { let index = calls; calls += 1; return index; }
fn main() {
    assert(values[next()] .!= values[next()]);
    assert(calls == 2);
    print("index order");
}
