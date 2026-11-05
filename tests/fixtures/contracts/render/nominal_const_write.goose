struct Number { value: i64 }
fn format(out: u8[>..]&, value: Number&) { value.value = 9; }
fn main() { const value = Number { 7 }; print(value); }
