extern fn bench_input() -> i64;
var calls = 0;
var global_values = [1, 2, 0];
var global_view: i64[:] = global_values[..];
fn insertion(xs: i64[:]) {
    for i in xs.len {
        var j = i; let v = xs[i];
        while j > 0 && xs[j - 1] > v { xs[j] = xs[j - 1]; j--; }
        xs[j] = v;
    }
}
fn insertion_i8(xs: i8[:]) {
    for i in xs.len {
        var j = i; let v = xs[i];
        while j > 0 && xs[j - 1] > v { xs[j] = xs[j - 1]; j--; }
        xs[j] = v;
    }
}
fn insertion_u32(xs: u32[:]) {
    for i in xs.len {
        var j = i; let v = xs[i];
        while j > 0 && xs[j - 1] > v { xs[j] = xs[j - 1]; j--; }
        xs[j] = v;
    }
}
fn disjunction(xs: i64[:], skip: bool, v: i64) {
    var j = 2;
    while j > 0 && (skip || xs[j - 1] > v) { xs[j] = xs[j - 1]; j--; }
}
fn comparison(xs: i64[:], j: i64) -> i64 { calls++; xs[j - 1] += 100; return 0; }
fn destination(xs: i64[:], j: i64) -> i64 { calls++; xs[j - 1] += 200; return j; }
fn impure(xs: i64[:], indexed: bool) {
    var j = 2;
    if indexed {
        while j > 0 && xs[j - 1] > 0 { xs[destination(xs, j)] = xs[j - 1]; j--; }
    } else {
        while j > 0 && xs[j - 1] > comparison(xs, j) { xs[j] = xs[j - 1]; j--; }
    }
}
fn reference(xs: i64[:]& ) {
    var j = 2;
    while j > 0 && xs[j - 1] > 0 { xs[j] = xs[j - 1]; j--; }
}
fn captured(xs: i64[:]) {
    recursive fn shift() {
        var j = 2;
        while j > 0 && xs[j - 1] > 0 { xs[j] = xs[j - 1]; j--; }
    }
    shift();
}
fn shadowed(xs: i64[:], n: i64) {
    var j = 2;
    while j > 0 && xs[j - 1] > 0 {
        var xs = [n + 20, n + 30, n + 40];
        xs[j] = xs[j - 1]; print(xs); j--;
    }
}
fn main() {
    let n = bench_input();
    var whole = [n % 7 - 3, (n * 5) % 13 - 6, n % 3 - 1, 4 - n % 5, n % 7 - 3];
    var partial = [91, n % 5 - 2, (n * 3) % 7 - 3, n % 3 - 1, n % 5 - 2,
                   2 - n % 4, (n * 11) % 9 - 4, -91];
    insertion(whole[..]); insertion(partial[1..7]); print(whole); print(partial);
    var rhs = [n + 1, n + 2, 0]; impure(rhs[..], false); print(rhs, " ", calls);
    calls = 0;
    var lhs = [n + 1, n + 2, 0]; impure(lhs[..], true); print(lhs, " ", calls);
    global_values[0] = n + 1; global_values[1] = n + 2;
    var j = 2;
    while j > 0 && global_view[j - 1] > 0 { global_view[j] = global_view[j - 1]; j--; }
    print(global_values);
    var ref_values = [n + 3, n + 4, 0]; var view: i64[:] = ref_values[..]; reference(view);
    var captured_values = [n + 5, n + 6, 0]; captured(captured_values[..]);
    print(ref_values, " ", captured_values);
    var original = [n + 1, n + 2, 0]; shadowed(original[..], n); print(original);
    var narrow: i8[6] = [-128, 127, -1, 0, 1, n as i8];
    var unsigned: u32[5] = [4294967295, 0, 2147483648, 7, n as u32];
    insertion_i8(narrow[..]); insertion_u32(unsigned[..]); print(narrow); print(unsigned);
    var bypass = [n + 11, n + 12, 0]; disjunction(bypass[..], n >= 0, n + 100); print(bypass);
    var descending = [n + 6, n + 5, n + 4, n + 3, n + 2, n + 1, n];
    insertion(descending[..]); print(descending);
}
