extern fn bench_input() -> i64;
enum Value { Empty, Number { x: i64 }, Many { xs: i64[3] } }

fn number(n: i64) -> Value.Number { Value.Number { n } }
fn borrowed(v: Value.Number&) -> Value.Number& { v }
fn make(n: i64) -> Value {
    if n < 0 { return Value.Empty; }
    if n == 0 { return number(30); }
    return Value.Many { [n, n + 1, n + 2] };
}
fn score(v: Value) -> i64 {
    match v { Empty => -1, Number p => p.x, Many p => p.xs[0] + p.xs[1] + p.xs[2] }
}
recursive fn descend(n: i64) -> Value {
    if n <= 0 { return make(0); }
    let previous = descend(n - 1);
    let sibling = make(n);
    return number(score(previous) + score(sibling));
}
fn mixed(n: i64) -> Value, i64, Value.Number {
    return make(n), n * 2, number(n + 7);
}
fn relay(n: i64) -> Value, i64, Value.Number {
    let a, b, c = mixed(n);
    return a, b, c;
}
fn main() {
    let n = bench_input();
    let a = make(n);
    let b = make(n + 1);
    print(score(a), " ", score(b), " ", score(descend(3)));
    let x, y, z = relay(n);
    print(score(x), " ", y, " ", z.x);
    let inline_value: Value = number(n + 50);
    print(score(inline_value));
    var array: Value[3] = [make(-1), number(n), make(1)];
    print(score(array[0]), " ", score(array[1]), " ", score(array[2]));
    let selected: Value = if n > 0 { make(2) } else { number(19) };
    let matched: Value = match n { 0 => number(22), _ => make(3) };
    print(score(selected), " ", score(matched));
    var payload = number(n + 100);
    let owned: Value = borrowed(payload);
    payload.x = -1000;
    print(score(owned));
}
