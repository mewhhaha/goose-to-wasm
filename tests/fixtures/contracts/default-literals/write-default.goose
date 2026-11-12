// Writing through a parameter instantiated read-only by its default is an error.
fn shout(text: u8[:] = "abc") { text[0] = 65; print(text); }
fn main() { shout(); }
