extern fn bench_input() -> i64;
var calls = 0;
fn make(n: i64) -> i64[>..] { calls++; return [n, n + 1]; }
fn simple(n: i64) -> i64[>..] { return [n, n + 1]; }
fn until(n: i64) -> i64[>..] { if n < 0 { return []; } return [n]; }
fn text() -> u8[>..] { return "ok"; }
fn first(values: const i64[:]) -> const i64& { return values[0]; }
fn sum(values: const i64[:]) -> i64 {
    var total = 0; for value in values { total += value; } return total;
}
fn keep(owned: i64[>..], view: const i64[:]) -> const i64[:] { owned.push(101); return view; }
inline fn relay(owned: i64[>..], view: const i64[:]) -> const i64[:] {
    let ignored = make(100).len;
    if ignored != 2 { abort("wrong body temporary"); } return view;
}
fn churn(a: i64[>..], b: i64[>..]) -> i64 { a[0] = 90; b[0] = 91; return a.len + b.len; }
fn observe(values: const i64[:], marker: i64) -> i64 { return values[0] + values[1] + marker; }
struct Defaulted { value: i64 = sum(simple(1)) }
fn main() {
    let n = bench_input();
    print(make(n).len, " ", make(n)[1], " ", calls);
    print(make(n), " ", make(n + 10), " ", calls);
    var values: i64[>..] = [1, 2]; copy(values); print(values, " ", copy(values));
    var appended: i64[>..] = []; appended.append(simple(n)); print(appended);
    var constructed: i64[>..] = [simple(n).len, sum(simple(n)[..])]; print(constructed);
    let scalar = first(make(n + 20)); print(scalar);
    print(observe(keep([100], make(n + 30)), churn([10, 11], [20, 21])));
    print(observe(relay([200], relay([300], make(n + 40))), churn([11, 12], [21, 22])));
    print(sum((if n > 0 { make(n + 50) } else { make(n + 60) })[..]), " ",
          observe((block { var owned: i64[>..] = [n + 70, n + 71]; break copy(owned); })[..], churn([1, 2], [3, 4])));
    print(observe((loop { break make(n + 80); })[..], churn([1, 2], [3, 4])));
    print(sum((match n { 0 => make(n + 90), _ => make(n + 100) })[..]));
    var total = 0;
    for value in make(n + 110) { make(200); churn([1, 2], [3, 4]); total += value; }
    print(total, " ", calls);
    var countdown = 3; while until(countdown).len > 0 { countdown--; } print(countdown);
    var steps = 0; while steps < 100 && simple(steps).len > 0 { steps++; } print(steps);
    var defaults = default<Defaulted[200]>(); print(defaults[0].value, " ", defaults[199].value);
    print(simple(n)[0], " ", text(), " ", constructed);
}
