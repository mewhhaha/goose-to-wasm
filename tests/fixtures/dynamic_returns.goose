extern fn bench_input() -> i64;
struct Borrowed { item: i64&, view: i64[:] }
var calls = 0;
fn make(n: i64) -> i64[>..] { calls++; return [n, n + 1]; }
var global: i64[>..] = make(7);
var source: i64[3] = [9, 10, 11];
fn local(n: i64) -> i64[>..] { var values: i64[>..] = [n]; values.push(n + 2); return values; }
fn choose(n: i64) -> i64[>..] { if n > 0 { [n, n + 1] } else { [] } }
fn explicit(n: i64) -> i64[>..] { if n < 0 { return [-1]; } return [n * 2]; }
fn fixed(n: i64) -> i64[2] { [n + 3, n + 4] }
fn from_fixed(n: i64) -> i64[>..] { return fixed(n); }
fn limited(n: i64) -> i64[..4] { return [n + 5]; }
fn from_limited(n: i64) -> i64[>..] { return limited(n); }
fn from_slice() -> i64[>..] { return source[..]; }
fn shrunk() -> i64[>..<] { var values: i64[>..<] = [1, 2]; values.pop(); return values; }
recursive fn forward(n: i64) -> i64[>..] {
    if n <= 0 { return local(20); }
    return forward(n - 1);
}
recursive fn even(n: i64) -> i64[>..] {
    if n <= 0 { return [40]; }
    return odd(n - 1);
}
recursive fn odd(n: i64) -> i64[>..] {
    if n <= 0 { return [41]; }
    return even(n - 1);
}
fn interrupt(n: i64) -> i64[>..] {
    return [1, if n > 0 { return [7, 8]; } else { 2 }, 3];
}
fn inner(n: i64) -> i64[>..] { return [n + 100]; }
fn outer(n: i64) -> i64[>..] { return [if n > 0 { return inner(n); } else { 0 }]; }
fn held(value: i64&, values: i64[:]) -> Borrowed[>..] { return [Borrowed { value, values }]; }
fn main() {
    let n = bench_input();
    let first = make(n); let second = make(n + 10);
    print(first, " ", second, " ", global, " ", calls);
    let a = local(n); let b = choose(n); let c = explicit(n);
    print(a, " ", b, " ", c);
    let f = from_fixed(n); let s = from_slice(); print(f, " ", s);
    let limited_result = from_limited(n); let adapted: i64[>..] = shrunk(); adapted.push(9);
    print(limited_result, " ", adapted);
    let recursive_result = forward(30); let mutual = even(31);
    print(recursive_result, " ", mutual);
    let interrupted = interrupt(n); let nested = outer(n);
    print(interrupted, " ", nested);
    var value = 10; var data: i64[2] = [20, 30];
    let borrowed = held(value, data[..]); value = 44; data[0] = 55;
    print(borrowed[0].item, " ", borrowed[0].view[0]);
    var sum = 0;
    for i in 10000 { let values = local(i); if i % 2 == 0 { continue; } sum += values[1]; }
    print(sum, " ", first, " ", second, " ", calls);
}
