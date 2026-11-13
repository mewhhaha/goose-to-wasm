// A negative count is rejected before anything changes.
fn main() {
    var a: i64[>..] = [];
    print(a.check_length(2));
    print(a.check_length(-1));
}
