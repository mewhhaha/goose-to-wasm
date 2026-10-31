extern fn bench_input() -> i64;
var shared: i64[>..] = [9, 8];
fn replace(var route: i64[>..]&, other: i64[>..]&, n: i64) {
    route = [if n > 0 { route .= other; 42 } else { 43 }, 44];
}
fn fixed(n: i64) -> i64[2] { return [n + 2, n + 3]; }
fn reset(n: i64) -> i64 {
    shared = [1, if n > 0 { return 7; } else { 2 }, 3]; return 0;
}
fn argument_exit(n: i64) -> i64 {
    shared = make(if n > 0 { return 8; } else { n }); return 0;
}
fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn owned(var values: i64[>..]) -> i64[>..] { values = [5, 6]; return values; }
fn dying(n: i64) -> i64 {
    var values: i64[>..] = [1];
    values = [if n > 0 { return 70; } else { 2 }; 1000000000];
    return values[0];
}
fn dying_parameter(values: i64[>..], n: i64) -> i64 {
    let alias: i64[>..]& = values;
    alias = [if n > 0 { return 71; } else { 2 }; 1000000000]; return alias[0];
}
fn abandoned_named(n: i64) -> i64[>..] {
    var values: i64[>..] = [1];
    values = [if n > 0 { return [72]; } else { 2 }; 1000000000]; return values;
}
fn main() {
    let n = bench_input();
    var values: i64[>..] = [1];
    values = [n, n + 1]; print(values);
    values = fixed(n); print(values);
    values = if n > 0 { [7, 8] } else { [] }; print(values);
    var blank: i64[>..] = []; blank = [33]; print(blank);
    values = copy(blank); blank[0] = 34; print(values, " ", blank);
    values = blank[..]; blank[0] = 35; print(values, " ", blank);
    var a: i64[>..] = [10]; var b: i64[>..] = [20];
    replace(a, b, 1); print(a, " ", b);
    print(reset(n), " ", shared.len, " ", shared[0]);
    shared = [10, 11, 12, 13];
    print(argument_exit(n), " ", shared.len, " ", shared[0]);
    let result = owned([1]); print(result);
    let named = abandoned_named(1);
    print(dying(1), " ", dying_parameter([1], 1), " ", named);
    var surviving: i64[>..] = [];
    for i in 10000 { surviving = [1, if i >= 0 { continue; } else { 2 }, 3]; }
    print(surviving.len, " ", surviving[0]);
}
