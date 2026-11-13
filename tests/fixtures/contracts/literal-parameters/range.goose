// A literal argument must fit every type its parameter adapts to inside the
// callee, here u8 through push (upstream §7.7).
fn push_some<A, T>(xs: A&, v: T, n: i64) { for i in n { xs.push(v); } }
fn main() {
    var flags: u8[>..] = [];
    push_some(flags, 300, 2);
    print(flags.len);
}
