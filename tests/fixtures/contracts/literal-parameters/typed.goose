// A typed argument binds its type variable: an i64 does not narrow into a
// byte array, however a literal call of the same function adapts.
fn push_some<A, T>(xs: A&, v: T, n: i64) { for i in n { xs.push(v); } }
fn main() {
    var flags: u8[>..] = [];
    push_some(flags, 1, 2);
    let n: i64 = 1;
    push_some(flags, n, 2);
    print(flags.len);
}
