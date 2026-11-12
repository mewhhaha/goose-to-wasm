// A string literal default is read-only, so its u8[:] parameter instantiates
// read-only, as for a literal argument; a caller's own buffer still binds.
fn show(text: u8[:] = "default") { print(text); }
fn count(text: u8[:], marker: u8[:] = "-") -> i64 { return text.len + marker.len; }
fn main() {
    show();
    var buffer: u8[>..] = [];
    buffer.append("buffer");
    show(buffer);
    print(count("ab"), " ", count("ab", "xyz"));
}
