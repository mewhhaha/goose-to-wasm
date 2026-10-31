extern fn bench_input() -> i64;
fn stop() -> i64 { return 9 from canceled; }
fn canceled() -> i64 { return [11, stop()] from target; }
fn target(mode: i64) -> i64[>..] {
    var values: i64[>..] = block {
        print(canceled());
        if mode == 0 { break [7]; }
        [7]
    };
    return values;
}
fn main() {
    var values = target(bench_input());
    print(values);
    values.push(8);
    print(values);
}
