// A canceled escape leaves physical data before the later normal result.
fn stop() -> i64 { return 9 from canceled; }
fn canceled() -> i64 { return [11, stop()] from target; }
fn seven() -> i64[>..] { return [7]; }
fn target(mode: i64) -> i64[>..] {
    print(canceled());
    if mode == 0 { return [7]; }
    if mode == 1 { return seven(); }
    let fixed: i64[1] = [7];
    return fixed;
}
fn main() {
    for mode in 0..3 {
        var values = target(mode);
        print(values);
        values.push(8);
        print(values);
    }
}
