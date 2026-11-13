fn ascii::is_digit(c: u8) -> bool { c - '0' < 10 }
fn ascii::hex_value(c: u8) -> i64 {
    if c - '0' < 10 { return c - '0'; }
    if (c | 32) - 'a' < 6 { return (c | 32) - 'a' + 10; }
    return -1;
}
fn text::ascii(s: u8[:]) -> i64 { s.len }
