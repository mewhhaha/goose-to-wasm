// An encoded integer component keeps its encoding in its own place between
// resizable components, up to the widest value, and reads back as a field,
// through a reference to its owner, from another owner's component and in
// the printed owner while the arrays beside it grow.
root struct Codes { before: i64[>..] = [], code: varint, after: u8[>..] = [] }

fn show(c: const Codes&) { print(c.code, " ", c.before.len, " ", c.after.len); }
fn main() {
    var small = Codes { code: -3, .. };
    var low = Codes { [1, 2], -9223372036854775807 - 1, "x" };
    var high = Codes { [3], 9223372036854775807, "yz" };
    for i in 10 { small.before.push(i); small.after.push('a'); low.after.push('b'); high.before.push(i); }
    show(small);
    show(low);
    show(high);
    var next = Codes { code: high.code - 1, .. };
    print(next.code + small.code);
    print(small.code, " ", low);
}
