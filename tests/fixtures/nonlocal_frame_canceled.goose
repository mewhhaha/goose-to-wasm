struct Frame { id: i64, values: i64[>..] }
fn stop() -> i64 { return 9 from canceled; }
fn canceled() -> i64 { return Frame { 7, [11, stop()] } from target; }
fn target(b: bool) -> Frame {
    var local = Frame { 1, [1, 2] };
    if b { print(canceled()); }
    return local;
}
fn main() {
    var value = target(true);
    print(value.id, " ", value.values);
    value.values.push(7);
    print(value.id, " ", value.values, " ", value.values.pop());
}
