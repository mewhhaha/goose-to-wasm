extern fn bench_input() -> i64;
var capcalls = 0;
fn capacity(n: i64) -> i64 { capcalls++; return n + 5; }
fn make(n: i64) -> i64[..] {
    var xs: i64[..] = [..capacity(n)]; xs.push(n); xs.push(n + 1); return xs;
}
inline fn empty(n: i64) -> i64[..] { return [..capacity(n)]; }
fn changed(xs: i64[..]) -> i64[..] { xs.push(77); return xs; }
fn bump(xs: i64[..]&) -> i64 { xs[0] += 10; xs.push(99); return xs.len; }
fn pair(n: i64) -> i64[..], i64, i64[..] {
    var xs = make(n); return xs, bump(xs), xs;
}
fn adapted(n: i64) -> i64[>..], i64, i64[] { return pair(n); }
fn fixed_pair(n: i64) -> i64[..4], i64, i64[..4] { return pair(n); }
fn grow(n: i64) -> i64[>..] { return [n, n + 1]; }
recursive fn forward(n: i64) -> i64[..] {
    if n <= 0 { return [..6]; } return forward(n - 1);
}
fn interrupted(xs: i64[..]&, n: i64) -> i64 {
    xs = [1, if n > 0 { return 77; } else { 2 }]; return 0;
}
fn main() {
    let n = bench_input(); var xs = make(n);
    let copied = copy(xs); let cut: i64[..] = xs[..];
    print(xs, " ", xs.len, " ", xs.cap, " ", copied.cap, " ", cut.cap);
    copied.push(7); print(copied, " ", xs, " ", changed(copy(xs)));
    xs = xs[1..]; print(xs, " ", xs.cap); xs.push(8); print(xs);
    let before = copy(xs); print(interrupted(xs, 1), " ", xs, " ", before);
    let a, count, b = pair(n); print(a, " ", a.cap, " ", count, " ", b, " ", b.cap);
    let aa, cc, bb = adapted(n); aa.push(100); print(aa, " ", cc, " ", bb);
    let fa, fc, fb = fixed_pair(n); print(fa, " ", fa.cap, " ", fc, " ", fb.cap);
    let from_grow: i64[..] = grow(n); print(from_grow, " ", from_grow.cap);
    let broad: i64[>..] = empty(n); for i in 20 { broad.push(i); } print(broad.len);
    let folded: i64[>..] = if true { empty(n) } else { empty(n) }; print(folded.len);
    let fixed: i64[..3] = empty(n); print(fixed.len, " ", fixed.cap);
    let tail = forward(20); tail.push(9); print(tail, " ", tail.cap, " ", capcalls);
}
