struct V { text: u8[] }
fn main() { var values = []; values = [V { "abc" }]; for value in values { print(value.text); } }
