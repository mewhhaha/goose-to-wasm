// A literal passed on through a second generic function is checked against
// the innermost use too (upstream §7.7).
fn push_some<A, T>(xs: A&, v: T, n: i64) { for i in n { xs.push(v); } }
fn fill2(xs, v) { push_some(xs, v, 2); }
fn main() {
    var flags: u8[>..] = [];
    fill2(flags, -1);
    print(flags.len);
}
