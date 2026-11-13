// An unsigned count does not wrap into an accepted signed one, and no count
// of elements beyond a data stack's reservation is accepted.
fn main() {
    var a: i64[>..] = [];
    let n: u64 = 18446744073709551615;
    print(a.check_length(268435456));
    print(a.check_length(n));
}
