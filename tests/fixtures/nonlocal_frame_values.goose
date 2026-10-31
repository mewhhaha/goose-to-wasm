extern fn bench_input() -> i64;
struct Frame { id: i64, values: i64[>..] }
fn invoke<C>(b: bool) -> i64, i64 { if b { C(); } return 0, 0; }
recursive fn maker(x: i64) -> Frame { return Frame { 7, [9] }; }
fn target(mode: i64) -> Frame {
    var local = Frame { 1, [1, 2] };
    invoke(mode > 0) {
        if mode == 1 { return Frame { 7, [9] }; }
        return maker(local.values.push(3));
    }
    return local;
}
fn main() {
    var value = target(bench_input());
    print(value.id, " ", value.values);
    value.values.push(10);
    print(value.id, " ", value.values);
}
