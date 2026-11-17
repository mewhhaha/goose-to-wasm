// Upstream accepts this store from a single argument with a merged view.
var g: u8[>..] = [71];
fn flag() -> bool { return g.len > 1; }
fn put(p: u8[:]&, q: u8[:]) { p = q; }
fn main() {
    var a: u8[>..] = [65];
    var b: u8[>..] = [66];
    var s = a[..];
    put(s, if flag() { g[..] } else { b[..] });
    print(s);
}
