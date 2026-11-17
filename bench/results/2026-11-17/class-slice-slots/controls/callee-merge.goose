// Upstream rejects this store. The two sources are separate on entry to put.
var g: u8[>..] = [71];
fn flag() -> bool { return g.len > 1; }
fn put(p: u8[:]&, x: u8[:], y: u8[:]) {
    p = if flag() { x } else { y };
}
fn main() {
    var a: u8[>..] = [65];
    var b: u8[>..] = [66];
    var s = a[..];
    put(s, g[..], b[..]);
    print(s);
}
