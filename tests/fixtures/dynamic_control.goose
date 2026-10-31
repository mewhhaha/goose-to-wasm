extern fn bench_input() -> i64;
enum Choice { Empty, Data { n: i64 } }
var calls = 0;
fn signal(n: i64) -> i64 { calls++; return n; }
fn blocked(n: i64) -> i64[>..] {
    return block {
        var owned: i64[>..] = [n]; owned.push(n + 1);
        if n > 0 { break owned; }
        break [n + 2];
    };
}
fn looped(n: i64) -> i64[>..] {
    var i = 0;
    return loop {
        var owned: i64[>..] = [n + i];
        if i < 2 { i++; continue; }
        break owned;
    };
}
fn matched(n: i64) -> i64[>..] {
    return match signal(n) {
        -1 => { return [99]; },
        0 => [],
        _ => { var values: i64[>..] = [n]; values.push(n + 1); values }
    };
}
fn payload(c: Choice) -> i64[>..] {
    return match c { Empty => [], Data value => [value.n, value.n + 1] };
}
fn main() {
    let n = bench_input();
    let a = blocked(n); let b = looped(n); let c = matched(n);
    let choice: Choice = if n > 0 { Choice.Data { n + 5 } } else { Choice.Empty };
    let d = payload(choice);
    print(a, " ", b, " ", c, " ", d, " ", calls);
    let direct: i64[>..] = block { loop { break; } break [n + 10]; };
    print(direct);
}
