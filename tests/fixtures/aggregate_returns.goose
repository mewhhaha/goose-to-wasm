// Owned results must survive the callee, later calls, and later result
// expressions. Exercise these rules before and after Goose's inlining pass.
extern fn bench_input() -> i64;

struct Pair { x: i64, y: i64 }
struct Bundle { values: Pair[2], tail: i64 }
struct Borrowed { item: i64&, pair: Pair }

var shared = Pair { 11, 22 };
var shared_values: i64[3] = [1, 2, 3];

fn make(value: i64) -> Pair { Pair { value, value * 2 } }
fn numbers(value: i64) -> i64[3] { [value, value + 1, value + 2] }
fn combine(a: Pair, b: Pair) -> Pair { Pair { a.x + b.x, a.y + b.y } }

recursive fn descend(n: i64) -> Pair {
    if n <= 0 { return make(0); }
    let previous = descend(n - 1);
    let sibling = make(100 + n);
    return Pair { previous.x + 1, previous.y + sibling.x };
}

recursive fn nested(n: i64) -> Bundle {
    if n <= 0 { return Bundle { [make(1), make(2)], 3 }; }
    let previous = nested(n - 1);
    return Bundle {
        [make(previous.values[0].x + 1), make(previous.values[1].x + 2)],
        previous.tail + 3,
    };
}

fn mutate_shared() -> i64 {
    shared.x = 99;
    shared.y = 77;
    return shared.x;
}

fn ordered() -> Pair, i64, Pair {
    shared = Pair { 11, 22 };
    return shared, mutate_shared(), shared;
}

fn forward() -> Pair, i64, Pair { return ordered(); }

fn mutate_values() -> i64 { shared_values[0] = 42; return 9; }
fn ordered_array() -> i64[3], i64 { return shared_values, mutate_values(); }

fn view_sum(values: const i64[:], later: Pair) -> i64 {
    var result = later.x;
    for value in values { result += value; }
    return result;
}

fn borrowed(value: i64&) -> Borrowed { Borrowed { item: value, pair: make(7) } }

fn loop_results(n: i64) -> Pair, i64 {
    var count = n;
    loop {
        loop {
            if count == 0 { return make(n), n * 3; }
            count--;
            break;
        }
    }
}

fn main() {
    let n = bench_input();
    let recursive_value = descend(n);
    let other = make(1000);
    print(recursive_value.x, " ", recursive_value.y, " ", other.x, " ", other.y);

    let both = combine(make(3), make(5));
    let first = numbers(10);
    let second = numbers(20);
    print(both.x, " ", both.y, " ", first, " ", second);

    let bundle = nested(n);
    print(bundle.values[0].x, " ", bundle.values[0].y, " ",
          bundle.values[1].x, " ", bundle.values[1].y, " ", bundle.tail);

    let before, change, after = forward();
    print(before.x, " ", before.y, " ", change, " ", after.x, " ", after.y);
    let old_values, marker = ordered_array();
    print(old_values, " ", marker, " ", shared_values);

    // A returned array used as a slice must also live in the caller.
    print(view_sum(numbers(5), make(7)));

    var value = 8;
    let reference = borrowed(value);
    value = 19;
    print(reference.item, " ", reference.pair.x, " ", reference.pair.y);

    let loop_pair, loop_scalar = loop_results(n);
    print(loop_pair.x, " ", loop_pair.y, " ", loop_scalar);
}
