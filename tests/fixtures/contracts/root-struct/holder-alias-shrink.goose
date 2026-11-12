// A reference stored in an owner field is seen through an owner alias.
root struct S { value: i64& }
fn bind(s: S&, v: i64&) { s.value .= v; }
fn main() {
    var a: i64[>..] = [1];
    var n = 2;
    var s = S { n };
    let alias = s;
    bind(s, a[0]);
    a.clear();
    print(alias.value);
}
