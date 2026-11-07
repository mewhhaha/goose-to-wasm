fn text(c: bool) -> u8[>..] { if c { return "left"; } else { return "right"; } }
fn main() { print(text(true), " ", text(false)); }
