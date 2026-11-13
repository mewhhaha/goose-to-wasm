// A literal argument to a bare type variable that no typed argument binds
// stays a literal inside the instance (upstream §7.7): the variable binds to
// the literal's default type, and the parameter adapts where it is used, as
// std's format_flt relies on in push_n(lead, '0', n).
fn push_some<A, T>(xs: A&, v: T, n: i64) { for i in n { xs.push(v); } }
fn put_at<A, T>(xs: A&, i: i64, v: T) {
    xs.push(v);
    var j = xs.len - 1;
    while j > i { xs[j] .= xs[j - 1]; j -= 1; }
    xs[i] .= v;
}
fn fill<A, T>(xs: A&, v: T, n: i64) { for i in n { xs.push(v); } }
// Passed on as a literal: the callee's uses constrain this call's literal.
fn fill2<A>(xs: A&, v) { fill(xs, v, 2); }
// The other branch types the literal, as it would a constant.
fn pick(c: bool, x: i16, v) -> i16 { if c { x } else { v } }
fn twice(v) { v + v }
fn main() {
    var text: u8[>..] = "ab";
    push_some(text, '0', 3);
    put_at(text, 0, '1');
    print(text);
    var fs: f32[>..] = [];
    fill(fs, 1.5, 2);
    var small: i16[..4] = [];
    fill(small, -7, 2);
    fill2(small, 300);
    var wide: i64[>..] = [];
    let n: i64 = 5;
    push_some(wide, n, 1);
    push_some(wide, 6, 1);
    print(fs, " ", small, " ", wide, " ", pick(false, 1, -3), " ", pick(true, 1, 5), " ", twice(21), " ", twice(1.25));
}
