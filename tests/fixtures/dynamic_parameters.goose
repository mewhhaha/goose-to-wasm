extern fn bench_input() -> i64;
struct Borrowed { item: i64&, view: i64[:] }
fn take(values: i64[>..], n: i64) -> i64 {
    for i in 100 { values.push(i); }
    values[0] += n;
    return values[0] + values.len;
}
fn transformed(values: i64[>..]) -> i64[>..] { values.push(99); return values; }
fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn shrink(values: i64[>..<]) -> i64 { let last = values.pop(); values.clear(); return last; }
fn mixed(values: i64[>..]) -> i64[2], i64 { return [values[0], values.len], values.len; }
fn borrowed(values: i64[>..]) -> i64 {
    let link: i64[>..]& = values;
    link.push(11);
    var sum = 0; for value in values { sum += value; }
    return sum;
}
fn item(values: Borrowed[>..]) -> i64& { return values[0].item; }
fn view(values: Borrowed[>..]) -> i64[:] { return values[0].view; }
fn later(values: i64[>..]&) -> i64 { values.push(30); return 4; }
fn pair(a: i64[>..], b: i64[>..]) -> i64 { return a.len * 100 + b[0]; }
fn isolated(a: i64[>..], b: i64[>..]) -> i64 { a[0] = 70; a.push(90); return a.len * 100 + b[0]; }
fn interrupted(n: i64) -> i64 { return take([1, if n > 0 { return 77; } else { 2 }], n); }
fn main() {
    let n = bench_input();
    var original: i64[>..] = [5];
    print(take(copy(original), n), " ", original);
    let changed = transformed(copy(original)); print(original, " ", changed);
    print(pair(copy(original), [later(original)]), " ", original);
    print(isolated(copy(original), copy(original)), " ", original);
    let fixed: i64[2] = [6, 7]; let limited: i64[..4] = [8];
    print(take(make(n), 1), " ", take(fixed, 1), " ", take(limited, 1), " ", shrink([3, 4]));
    let summary, length = mixed([12, 13, 14]); print(summary, " ", length, " ", borrowed([7]));
    var number = 8; var data: i64[2] = [9, 10];
    let ref: const i64& = item([Borrowed { number, data[..] }]);
    let slice = view([Borrowed { number, data[..] }]);
    number = 20; data[0] = 30; print(ref, " ", slice);
    var sum = 0;
    for i in 10000 { sum += interrupted(i % 2); }
    print(sum, " ", ref, " ", slice, " ", original);
}
