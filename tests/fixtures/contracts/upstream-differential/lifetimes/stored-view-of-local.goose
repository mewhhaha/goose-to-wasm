// A view of an inner local cannot be stored into an outer array, which
// outlives the local.
fn main() {
    var outer: (const i64[:])[>..] = [];
    { var xs: i64[] = [7, 8]; outer.push(xs[..]); }
    print(outer.len);
}
