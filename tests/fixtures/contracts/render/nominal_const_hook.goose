struct Number { value: i64 }
fn format(out: u8[>..]&, value: const Number&) { format(out, "#", value.value); }
fn main() {
    const value = Number { 7 };
    print("readonly:", value);
    print("nested:", [value, value]);
}
