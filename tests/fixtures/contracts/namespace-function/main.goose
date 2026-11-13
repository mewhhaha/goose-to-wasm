// A function and a namespace may share a name (upstream §11.1): a call
// names the function, and a qualified name the namespace's declaration,
// whichever is declared first and whichever file declares it.
import imported.ascii;

fn ascii(s: u8[:]) -> i64 {
    var n = 0;
    for c in s { if ascii::is_digit(c) { n += ascii::hex_value(c); } }
    return n;
}
fn ascii::is_space(c: u8) -> bool { c == ' ' }
fn main() {
    print(ascii("a1 b23"), " ", ascii::hex_value('f'), " ", ascii::is_space(' '));
    print(text::ascii("q"));
}
