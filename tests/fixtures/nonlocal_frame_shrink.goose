struct Frame { id: i64, values: i64[>..<] }
recursive fn leave() { return Frame { 7, [9, 10] } from target; }
fn target() -> Frame { var local = Frame { 1, [1, 2] }; leave(); return local; }
fn main() {
    var value = target();
    print(value.id, " ", value.values);
    print(value.values.pop());
    value.values.resize(3, 11);
    print(value.values);
    value.values.clear();
    value.values.push(12);
    print(value.values);
}
