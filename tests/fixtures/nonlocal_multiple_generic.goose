struct Frame { id: i64, values: i64[>..] }
fn pair<T>(value: T) -> T, T {
    recursive fn leave() { return copy(value), copy(value) from pair; }
    leave(); return copy(value), copy(value);
}
fn main() {
    var scalar: i64 = 7;
    let a, b = pair(scalar); print(a," ",b);
    var source: i64[>..] = [1, 2];
    var left, right = pair(copy(source)); left[0] = 9;
    print(source," ",left," ",right);
    var frame = Frame { 3, [4, 5] };
    var first, second = pair(copy(frame)); first.values[0] = 8; first.id = 9;
    print(frame.id," ",frame.values," ",first.id," ",first.values," ",second.id," ",second.values);
}
